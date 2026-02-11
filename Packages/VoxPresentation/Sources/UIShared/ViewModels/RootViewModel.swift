import Foundation
import Combine
import CoreModels
import SwiftUI

/// 根视图 ViewModel
///
/// 组合 `SessionListViewState` 和 `EditorViewState`，管理导航与全局 UI 状态。
@MainActor
public final class RootViewModel<SL: SessionListViewState, E: EditorViewState>: ObservableObject, RootViewState {

    // MARK: - 子 ViewModel

    public let sessionListState: SL
    public let editorState: E

    // MARK: - 导航状态

    @Published public var recorderStatus: RecorderStatus = .idle
    @Published public var isDrawerOpen: Bool = false
    @Published public var showRawSheet: Bool = false
    @Published public var navigationPath: [Route] = []

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init(sessionListState: SL, editorState: E) {
        self.sessionListState = sessionListState
        self.editorState = editorState

        bindEditorState()
        loadHistoryOnLaunch()
    }

    private func bindEditorState() {
        // 将 Editor 的 isRecording/isRefining 映射到 RecorderStatus
        editorState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateRecorderStatus()
            }
            .store(in: &cancellables)
    }

    private func updateRecorderStatus() {
        if editorState.isRecording {
            recorderStatus = .listening
        } else if editorState.isRefining {
            recorderStatus = .refining
        } else if editorState.errorMessage != nil {
            recorderStatus = .error
        } else {
            recorderStatus = .idle
        }
    }

    // MARK: - 操作

    public func selectSession(_ id: UUID) {
        Task {
            await sessionListState.selectSession(id)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isDrawerOpen = false
        }
    }

    public func navigateToMe() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isDrawerOpen = false
        }
        navigationPath.append(.me)
    }

    public func toggleDrawer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isDrawerOpen.toggle()
        }
    }

    public func createNewSession() {
        Task {
            await sessionListState.createSession()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isDrawerOpen = false
        }
        navigationPath.removeAll()
    }

    private func loadHistoryOnLaunch() {
        Task {
            await sessionListState.loadSessions()
        }
    }
}
