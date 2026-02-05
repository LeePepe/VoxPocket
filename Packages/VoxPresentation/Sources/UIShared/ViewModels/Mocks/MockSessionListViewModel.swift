import Foundation
import Combine
import CoreModels

/// Preview 用 Mock 会话列表 ViewModel
@MainActor
public final class MockSessionListViewModel: ObservableObject, SessionListViewState {

    @Published public var sessions: [Session]
    @Published public var isLoading: Bool = false
    @Published public var selectedSessionId: UUID?
    @Published public var searchQuery: String = ""
    @Published public var errorMessage: String?

    public var filteredSessions: [Session] {
        guard !searchQuery.isEmpty else { return sessions }
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    public init(sessions: [Session]? = nil) {
        let sampleSessions = sessions ?? Self.sampleSessions
        self.sessions = sampleSessions
        self.selectedSessionId = sampleSessions.first?.id
    }

    public func loadSessions() async {}
    public func createSession() async {}
    public func deleteSession(_ id: UUID) async {}

    public func selectSession(_ id: UUID) async {
        selectedSessionId = id
    }

    public func refresh() async {}
    public func clearError() { errorMessage = nil }

    // MARK: - 示例数据

    public static let sampleSessions: [Session] = [
        Session(
            id: UUID(),
            title: "客户反馈集中在首屏加载速度与登录重试",
            createdAt: Date().addingTimeInterval(-3600),
            updatedAt: Date().addingTimeInterval(-3600),
            state: .idle
        ),
        Session(
            id: UUID(),
            title: "本周目标是把语音纠错流程打通，重点在撤销与重做",
            createdAt: Date().addingTimeInterval(-8600),
            updatedAt: Date().addingTimeInterval(-8600),
            state: .refining
        ),
        Session(
            id: UUID(),
            title: "旅行清单：护照、充电器、行程确认邮件",
            createdAt: Date().addingTimeInterval(-17200),
            updatedAt: Date().addingTimeInterval(-17200),
            state: .idle
        ),
    ]
}
