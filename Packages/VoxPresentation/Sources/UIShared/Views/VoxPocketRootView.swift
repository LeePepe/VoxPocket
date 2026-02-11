import SwiftUI
import CoreModels

public struct VoxPocketRootView<VM: RootViewState>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var viewModel: VM
    @State private var sidebarSelection: SidebarDestination?
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .detailOnly
    let onCopyRefined: (String) -> Void
    let onCopyRaw: (String) -> Void
 
    public init(
        viewModel: VM,
        onCopyRefined: @escaping (String) -> Void = { _ in },
        onCopyRaw: @escaping (String) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onCopyRefined = onCopyRefined
        self.onCopyRaw = onCopyRaw
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.sessionListState.searchQuery },
            set: { viewModel.sessionListState.searchQuery = $0 }
        )
    }

    private var isCompactPhone: Bool {
#if os(iOS)
        return horizontalSizeClass == .compact
#else
        return false
#endif
    }

    public var body: some View {
        Group {
            if isCompactPhone {
                iPhoneShellView
            } else {
                splitViewShell
            }
        }
        .ignoresSafeArea()
        .onAppear {
            syncSidebarSelection()
        }
        .onChange(of: viewModel.sessionListState.selectedSessionId) { _, _ in
            syncSidebarSelection()
        }
        .onChange(of: viewModel.sessionListState.filteredSessions.map(\.id)) { _, _ in
            if viewModel.sessionListState.selectedSessionId == nil,
               let firstID = viewModel.sessionListState.filteredSessions.first?.id {
                viewModel.selectSession(firstID)
            } else {
                syncSidebarSelection()
            }
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneShellView: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            DrawerSplitContainer(isOpen: $viewModel.isDrawerOpen) {
                SidebarDrawerView(
                    sessions: viewModel.sessionListState.filteredSessions,
                    selectedSessionID: viewModel.sessionListState.selectedSessionId ?? UUID(),
                    isRecording: viewModel.recorderStatus == .listening,
                    searchText: searchQueryBinding,
                    onSelectSession: { session in
                        viewModel.selectSession(session.id)
                    },
                    onNewSession: {
                        viewModel.createNewSession()
                    },
                    onOpenMe: {
                        viewModel.navigateToMe()
                    }
                )
            } content: {
                HomeRecorderView(
                    viewModel: viewModel.editorState,
                    recorderStatus: viewModel.recorderStatus,
                    onCopyRefined: onCopyRefined,
                    onCopyRaw: onCopyRaw
                )
                .navigationTitle("VoxPocket")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: { viewModel.toggleDrawer() }) {
                            Image(systemName: "line.3.horizontal")
                        }
                    }
                    ToolbarItemGroup(placement: .automatic) {
                        Button(action: { viewModel.editorState.undo() }) {
                            Image(systemName: "arrow.uturn.left")
                        }
                        .disabled(!viewModel.editorState.canUndo)

                        Button(action: { viewModel.editorState.redo() }) {
                            Image(systemName: "arrow.uturn.right")
                        }
                        .disabled(!viewModel.editorState.canRedo)

                        Button(action: { viewModel.showRawSheet = true }) {
                            Label("Raw", systemImage: "waveform.and.mic")
                        }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .me:
                    MeRootView(status: viewModel.recorderStatus)
                }
            }
        }
#if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
#else
        .toolbarBackground(.hidden, for: .windowToolbar)
#endif
        .sheet(isPresented: $viewModel.showRawSheet) {
            let rawText = viewModel.editorState.isRecording
                ? viewModel.editorState.liveTranscription
                : viewModel.editorState.rawTranscription
            RawTranscriptView(
                rawText: rawText,
                status: viewModel.recorderStatus,
                canCopyRaw: !rawText.isEmpty,
                onCopyRaw: {
                    onCopyRaw(rawText)
                }
            )
        }
    }

    // MARK: - iPad / Mac Layout

    private var splitViewShell: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            VStack(spacing: 0) {
                List(selection: $sidebarSelection) {
                    ForEach(viewModel.sessionListState.filteredSessions) { session in
                        NavigationLink(value: SidebarDestination.session(session.id)) {
                            HistoryRowView(session: session)
                        }
                    }
                }
                .listStyle(.sidebar)
                .searchable(
                    text: searchQueryBinding,
                    placement: .sidebar,
                    prompt: "Search history"
                )
                .onChange(of: sidebarSelection) { _, newValue in
                    switch newValue {
                    case .session(let id):
                        viewModel.selectSession(id)
                    case .me:
                        break
                    case .none:
                        break
                    }
                }

                Divider()

                Button {
                    sidebarSelection = .me
                } label: {
                    MeEntryRow()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(sidebarSelection == .me ? Color.white.opacity(0.14) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .navigationTitle("VoxPocket")
            .toolbar {
                if splitViewVisibility != .detailOnly {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.createNewSession()
                            sidebarSelection = nil
                            syncSidebarSelection()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
#endif
        } detail: {
            switch sidebarSelection {
            case .session, .none:
                HomeRecorderView(
                    viewModel: viewModel.editorState,
                    recorderStatus: viewModel.recorderStatus,
                    onCopyRefined: onCopyRefined,
                    onCopyRaw: onCopyRaw
                )
                .navigationTitle("VoxPocket")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button(action: { viewModel.editorState.undo() }) {
                            Image(systemName: "arrow.uturn.left")
                        }
                        .disabled(!viewModel.editorState.canUndo)

                        Button(action: { viewModel.editorState.redo() }) {
                            Image(systemName: "arrow.uturn.right")
                        }
                        .disabled(!viewModel.editorState.canRedo)

#if os(iOS)
                        Button(action: { viewModel.showRawSheet = true }) {
                            Label("Raw", systemImage: "waveform.and.mic")
                        }
#endif
                    }
                }
                .sheet(isPresented: $viewModel.showRawSheet) {
                    let rawText = viewModel.editorState.isRecording
                        ? viewModel.editorState.liveTranscription
                        : viewModel.editorState.rawTranscription
                    RawTranscriptView(
                        rawText: rawText,
                        status: viewModel.recorderStatus,
                        canCopyRaw: !rawText.isEmpty,
                        onCopyRaw: {
                            onCopyRaw(rawText)
                        }
                    )
                }
            case .me:
                MeRootView(status: viewModel.recorderStatus)
            }
        }
#if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
#else
        .toolbarBackground(.hidden, for: .windowToolbar)
#endif
    }

    private func syncSidebarSelection() {
        if let id = viewModel.sessionListState.selectedSessionId {
            sidebarSelection = .session(id)
            return
        }
        if let firstID = viewModel.sessionListState.filteredSessions.first?.id {
            sidebarSelection = .session(firstID)
            return
        }
        sidebarSelection = nil
    }
}
#Preview {
    VoxPocketRootView(
        viewModel: RootViewModel(
            sessionListState: MockSessionListViewModel(),
            editorState: MockEditorViewModel()
        )
    )
}
