import Foundation
import Combine
import CoreModels

/// 内存会话用例
///
/// 在内存中管理会话生命周期，不依赖持久化层。
/// 适用于尚未接入持久化存储的阶段。
public final class InMemorySessionUseCase: SessionUseCase, @unchecked Sendable {

    // MARK: - 状态

    private var sessions: [Session] = []
    private let sessionsSubject = CurrentValueSubject<[Session], Error>([])
    private let currentSessionSubject = CurrentValueSubject<Session?, Never>(nil)

    // MARK: - SessionUseCase

    public var currentSession: Session? {
        currentSessionSubject.value
    }

    public var currentSessionPublisher: AnyPublisher<Session?, Never> {
        currentSessionSubject.eraseToAnyPublisher()
    }

    public var sessionsPublisher: AnyPublisher<[Session], Error> {
        sessionsSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    public init() {}

    // MARK: - 操作

    public func createSession(title: String?) async throws -> Session {
        let now = Date()
        let session = Session(
            id: UUID(),
            title: title ?? now.formatted(date: .abbreviated, time: .shortened),
            createdAt: now,
            updatedAt: now,
            state: .idle
        )
        sessions.insert(session, at: 0)
        sessionsSubject.send(sessions)
        currentSessionSubject.send(session)
        return session
    }

    public func loadSession(_ id: UUID) async throws {
        guard let session = sessions.first(where: { $0.id == id }) else {
            throw NSError(domain: "InMemorySessionUseCase", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "会话不存在"])
        }
        currentSessionSubject.send(session)
    }

    public func saveCurrentSession() async throws {
        // 内存模式无需额外保存
    }

    public func fetchAllSessions() async throws -> [Session] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func deleteSession(_ id: UUID) async throws {
        sessions.removeAll { $0.id == id }
        sessionsSubject.send(sessions)
        if currentSession?.id == id {
            currentSessionSubject.send(nil)
        }
    }

    public func updateSessionTitle(_ id: UUID, title: String) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index] = Session(
            id: sessions[index].id,
            title: title,
            createdAt: sessions[index].createdAt,
            updatedAt: Date(),
            state: sessions[index].state
        )
        sessionsSubject.send(sessions)
    }

    public func closeCurrentSession() async throws {
        currentSessionSubject.send(nil)
    }
}
