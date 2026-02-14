import Foundation
import Combine
import SwiftData
import CoreModels

/// SwiftData 实现的会话仓储
///
/// 每次操作创建独立 ModelContext，避免：
/// 1. 使用 mainContext 触发 SwiftUI 自动观察导致 UI 卡死
/// 2. ModelContext 跨线程使用导致 "Unbinding from the main queue" 警告
public final class SwiftDataSessionRepository: SessionRepository, @unchecked Sendable {

    private let container: ModelContainer
    private let sessionsSubject = CurrentValueSubject<[Session], Error>([])

    public init(container: ModelContainer) {
        self.container = container
    }

    /// 创建一次性 ModelContext
    private func makeContext() -> ModelContext {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        return ctx
    }

    // MARK: - SessionRepository

    public func fetchAll() async throws -> [Session] {
        let ctx = makeContext()
        let descriptor = FetchDescriptor<SessionRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let records = try ctx.fetch(descriptor)
        let sessions = records.map { $0.toDomain() }
        sessionsSubject.send(sessions)
        return sessions
    }

    public func fetch(by id: UUID) async throws -> Session? {
        let ctx = makeContext()
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try ctx.fetch(descriptor).first?.toDomain()
    }

    public func save(_ session: Session) async throws {
        let ctx = makeContext()
        let sessionId = session.id
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.id == sessionId }
        )
        if let existing = try ctx.fetch(descriptor).first {
            existing.update(from: session)
        } else {
            ctx.insert(SessionRecord(from: session))
        }
        try ctx.save()
        // 更新观察者
        _ = try await fetchAll()
    }

    public func delete(_ session: Session) async throws {
        try await delete(by: session.id)
    }

    public func delete(by id: UUID) async throws {
        let ctx = makeContext()
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let record = try ctx.fetch(descriptor).first {
            ctx.delete(record)
            try ctx.save()
        }
        _ = try await fetchAll()
    }

    public func observe() -> AnyPublisher<[Session], Error> {
        sessionsSubject.eraseToAnyPublisher()
    }

    public func observe(id: UUID) -> AnyPublisher<Session?, Error> {
        sessionsSubject
            .map { sessions in
                sessions.first { $0.id == id }
            }
            .eraseToAnyPublisher()
    }

    public func search(query: String) async throws -> [Session] {
        let ctx = makeContext()
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate {
                $0.title.localizedStandardContains(query)
                || $0.rawText.localizedStandardContains(query)
                || $0.refinedText.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try ctx.fetch(descriptor).map { $0.toDomain() }
    }
}
