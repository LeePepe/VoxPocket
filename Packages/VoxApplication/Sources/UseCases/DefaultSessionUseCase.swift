import Foundation
import Combine
import CoreModels
import Persistence

/// 持久化会话用例
///
/// 委托 `SessionRepository` 进行持久化操作。
public final class DefaultSessionUseCase: SessionUseCase, @unchecked Sendable {

    private let repository: SessionRepository
    private let currentSessionSubject = CurrentValueSubject<Session?, Never>(nil)

    public var currentSession: Session? {
        currentSessionSubject.value
    }

    public var currentSessionPublisher: AnyPublisher<Session?, Never> {
        currentSessionSubject.eraseToAnyPublisher()
    }

    public var sessionsPublisher: AnyPublisher<[Session], Error> {
        repository.observe()
    }

    public init(repository: SessionRepository) {
        self.repository = repository
    }

    public func createSession(title: String?) async throws -> Session {
        let now = Date()
        let session = Session(
            id: UUID(),
            title: title ?? now.formatted(date: .abbreviated, time: .shortened),
            createdAt: now,
            updatedAt: now,
            state: .idle
        )
        try await repository.save(session)
        currentSessionSubject.send(session)
        return session
    }

    public func loadSession(_ id: UUID) async throws {
        guard let session = try await repository.fetch(by: id) else {
            throw NSError(domain: "DefaultSessionUseCase", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "会话不存在"])
        }
        currentSessionSubject.send(session)
    }

    public func saveCurrentSession() async throws {
        guard let session = currentSession else { return }
        try await repository.save(session)
    }

    public func fetchAllSessions() async throws -> [Session] {
        try await repository.fetchAll()
    }

    public func deleteSession(_ id: UUID) async throws {
        try await repository.delete(by: id)
        if currentSession?.id == id {
            currentSessionSubject.send(nil)
        }
    }

    public func updateSessionTitle(_ id: UUID, title: String) async throws {
        guard var session = try await repository.fetch(by: id) else { return }
        session.title = title
        session.updatedAt = Date()
        try await repository.save(session)
    }

    public func closeCurrentSession() async throws {
        if let session = currentSession {
            try await repository.save(session)
        }
        currentSessionSubject.send(nil)
    }

    @discardableResult
    public func saveCompletedSession(title: String?, rawText: String, refinedText: String) async throws -> Session {
        let displayText = refinedText.isEmpty ? rawText : refinedText
        let autoTitle = title ?? String(displayText.prefix(20))
        let now = Date()
        let session = Session(
            id: UUID(),
            title: autoTitle,
            rawText: rawText,
            refinedText: refinedText,
            createdAt: now,
            updatedAt: now,
            state: .idle
        )
        try await repository.save(session)
        return session
    }
}
