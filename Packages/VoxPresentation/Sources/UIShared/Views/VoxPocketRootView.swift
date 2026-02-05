import SwiftUI
import CoreModels

public struct VoxPocketRootView<VM: RootViewState>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var viewModel: VM
    @State private var sidebarSelection: SidebarDestination = .session(UUID())
 
    public init(viewModel: VM) {
        self.viewModel = viewModel
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
        .background(
            BackgroundAtmosphere(
                status: viewModel.recorderStatus,
                audioLevel: Double(viewModel.editorState.audioLevel)
            )
        )
        .ignoresSafeArea()
        .onAppear {
            if let id = viewModel.sessionListState.selectedSessionId {
                sidebarSelection = .session(id)
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
                    onOpenMe: {
                        viewModel.navigateToMe()
                    }
                )
            } content: {
                HomeRecorderView(
                    viewModel: viewModel.editorState,
                    recorderStatus: viewModel.recorderStatus,
                    onToggleSidebar: {
                        viewModel.toggleDrawer()
                    },
                    onShowRawSheet: {
                        viewModel.showRawSheet = true
                    }
                )
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .me:
                    MeRootView(status: viewModel.recorderStatus)
                }
            }
        }
        .sheet(isPresented: $viewModel.showRawSheet) {
            RawTranscriptView(
                rawText: viewModel.editorState.liveTranscription,
                status: viewModel.recorderStatus
            )
        }
    }

    // MARK: - iPad / Mac Layout

    private var splitViewShell: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section {
                    ForEach(viewModel.sessionListState.filteredSessions) { session in
                        NavigationLink(value: SidebarDestination.session(session.id)) {
                            HistoryRowView(session: session)
                        }
                    }
                } header: {
                    SidebarHeaderView(isRecording: viewModel.recorderStatus == .listening)
                }

                Section {
                    NavigationLink(value: SidebarDestination.me) {
                        MeEntryRow()
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
                if case let .session(id) = newValue {
                    viewModel.selectSession(id)
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
#endif
        } detail: {
            switch sidebarSelection {
            case .session:
                HomeRecorderView(
                    viewModel: viewModel.editorState,
                    recorderStatus: viewModel.recorderStatus,
                    onToggleSidebar: nil,
                    onShowRawSheet: {
                        viewModel.showRawSheet = true
                    }
                )
                .sheet(isPresented: $viewModel.showRawSheet) {
                    RawTranscriptView(
                        rawText: viewModel.editorState.liveTranscription,
                        status: viewModel.recorderStatus
                    )
                }
            case .me:
                MeRootView(status: viewModel.recorderStatus)
            }
        }
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
