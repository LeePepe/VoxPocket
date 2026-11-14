import SwiftUI
import CoreModels

public struct VoxPocketRootView<VM: RootViewState>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var viewModel: VM
    @StateObject private var llmSettings = LLMProviderSettingsViewModel()
    @State private var sidebarSelection: SidebarDestination?
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .detailOnly
    let onCopyRefined: (String) -> Void
    let onCopyRaw: (String) -> Void
    var localModelLoadingStatus: LocalModelLoadingStatus?

    public init(
        viewModel: VM,
        onCopyRefined: @escaping (String) -> Void = { _ in },
        onCopyRaw: @escaping (String) -> Void = { _ in },
        localModelLoadingStatus: LocalModelLoadingStatus? = nil
    ) {
        self.viewModel = viewModel
        self.onCopyRefined = onCopyRefined
        self.onCopyRaw = onCopyRaw
        self.localModelLoadingStatus = localModelLoadingStatus
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
        .voxTheme()
        .sheet(isPresented: $viewModel.showRawSheet) {
            let raw = viewModel.editorState.isRecording ? viewModel.editorState.liveTranscription : viewModel.editorState.rawTranscription
            RawTranscriptView(rawText: raw, status: viewModel.recorderStatus, canCopyRaw: !raw.isEmpty, onCopyRaw: { onCopyRaw(raw) })
        }
        .onAppear {
            syncSidebarSelection()
            Task { await llmSettings.load() }
        }
        .onChange(of: viewModel.sessionListState.selectedSessionId) { _, _ in
            syncSidebarSelection()
        }
        .onChange(of: viewModel.sessionListState.filteredSessions.map(\.id)) { _, _ in
            if viewModel.sessionListState.selectedSessionId == nil {
                // 启动时始终创建新 session，保证编辑器以空白状态开始
                viewModel.createNewSession()
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
                    onDeleteSession: { session in
                        viewModel.deleteSession(session.id)
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
                    onCopyRaw: onCopyRaw,
                    onOpenTodoList: { viewModel.toggleDrawer() },
                    onOpenSettings: { viewModel.navigateToMe() }
                )
#if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
#else
                .toolbar(.hidden, for: .windowToolbar)
#endif

            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .me:
                    settingsSurface
                }
            }
        }
#if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
#else
        .toolbarBackground(.hidden, for: .windowToolbar)
#endif

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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteSession(session.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
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
                    onCopyRaw: onCopyRaw,
                    onOpenTodoList: { splitViewVisibility = .all; sidebarSelection = .session(viewModel.sessionListState.selectedSessionId ?? UUID()) },
                    onOpenSettings: { splitViewVisibility = .all; sidebarSelection = .me }
                )
#if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
#else
                .toolbar(.hidden, for: .windowToolbar)
#endif
            case .me:
                settingsSurface
            }
        }
#if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
#else
        .toolbarBackground(.hidden, for: .windowToolbar)
#endif
    }

    private var settingsSurface: some View {
        VStack(spacing: 0) {
            EditorSecondaryControls(viewModel: viewModel.editorState, llmSettings: llmSettings) {
                viewModel.showRawSheet = true
            }
            MeRootView(status: viewModel.recorderStatus, onDeleteAllHistory: { viewModel.deleteAllSessions() }, localModelLoadingStatus: localModelLoadingStatus)
        }
        .navigationTitle("设置")
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

private struct EditorSecondaryControls<VM: EditorViewState>: View {
    @ObservedObject var viewModel: VM
    @ObservedObject var llmSettings: LLMProviderSettingsViewModel
    let showRaw: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { actions }
            VStack { actions }
        }
        .padding(16)
    }

    @ViewBuilder private var actions: some View {
        Button("撤销", systemImage: "arrow.uturn.left") { viewModel.undo() }
            .disabled(!viewModel.canUndo).frame(minHeight: 44).accessibilityIdentifier("vox.editor.undo")
        Button("重做", systemImage: "arrow.uturn.right") { viewModel.redo() }
            .disabled(!viewModel.canRedo).frame(minHeight: 44).accessibilityIdentifier("vox.editor.redo")
        Button("原始转写", systemImage: "waveform.and.mic", action: showRaw)
            .frame(minHeight: 44).accessibilityIdentifier("vox.editor.raw")
        Button(llmSettings.skipContentAnalysis ? "开启意图分析" : "跳过意图分析", systemImage: "wand.and.sparkles") {
            Task { await llmSettings.updateSkipContentAnalysis(!llmSettings.skipContentAnalysis) }
        }
        .frame(minHeight: 44).accessibilityIdentifier("vox.editor.refine.toggle")
    }
}
