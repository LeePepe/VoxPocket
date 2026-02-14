import Foundation
import Combine
import CoreModels
import UseCases

/// 会话列表 ViewModel
///
/// 桥接 `SessionUseCase` 到 `SessionListViewState` 协议。
@MainActor
public final class SessionListViewModel: ObservableObject, SessionListViewState {

    // MARK: - 依赖

    private let sessionUseCase: SessionUseCase
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published 状态

    @Published public var sessions: [Session] = []
    @Published public var isLoading: Bool = false
    @Published public var selectedSessionId: UUID?
    @Published public var searchQuery: String = ""
    @Published public var errorMessage: String?

    // MARK: - 计算属性

    public var filteredSessions: [Session] {
        guard !searchQuery.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(searchQuery)
            || session.displayText.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // MARK: - Init

    public init(sessionUseCase: SessionUseCase) {
        self.sessionUseCase = sessionUseCase
        bindUseCase()
    }

    private func bindUseCase() {
        sessionUseCase.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .catch { [weak self] error -> Empty<[Session], Never> in
                self?.errorMessage = error.localizedDescription
                return Empty()
            }
            .assign(to: &$sessions)
    }

    // MARK: - 操作

    public func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await sessionUseCase.fetchAllSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createSession() async {
        do {
            let session = try await sessionUseCase.createSession(title: nil)
            selectedSessionId = session.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteSession(_ id: UUID) async {
        do {
            try await sessionUseCase.deleteSession(id)
            if selectedSessionId == id {
                selectedSessionId = sessions.first(where: { $0.id != id })?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteAllSessions() async {
        let allIds = sessions.map(\.id)
        for id in allIds {
            do {
                try await sessionUseCase.deleteSession(id)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        selectedSessionId = nil
    }

    public func selectSession(_ id: UUID) async {
        selectedSessionId = id
        do {
            try await sessionUseCase.loadSession(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        await loadSessions()
    }

    public func clearError() {
        errorMessage = nil
    }
}
