import Foundation
import Combine
import SwiftData
import CoreModels

/// SwiftData 实现的会话仓储
///
/// 通过 ModelContainer 进行持久化，支持 CloudKit 同步。
public final class SwiftDataSessionRepository: SessionRepository, @unchecked Sendable {

    private let container: ModelContainer
    private let sessionsSubject = CurrentValueSubject<[Session], Error>([])

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - SessionRepository

    public func fetchAll() async throws -> [Session] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<SessionRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let records = try container.mainContext.fetch(descriptor)
            let sessions = records.map { $0.toDomain() }
            sessionsSubject.send(sessions)
            return sessions
        }
    }

    public func fetch(by id: UUID) async throws -> Session? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<SessionRecord>(
                predicate: #Predicate { $0.id == id }
            )
            return try container.mainContext.fetch(descriptor).first?.toDomain()
        }
    }

    public func save(_ session: Session) async throws {
        try await MainActor.run {
            let ctx = container.mainContext
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
        }
        // 更新观察者
        _ = try await fetchAll()
    }

    public func delete(_ session: Session) async throws {
        try await delete(by: session.id)
    }

    public func delete(by id: UUID) async throws {
        try await MainActor.run {
            let ctx = container.mainContext
            let descriptor = FetchDescriptor<SessionRecord>(
                predicate: #Predicate { $0.id == id }
            )
            if let record = try ctx.fetch(descriptor).first {
                ctx.delete(record)
                try ctx.save()
            }
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
        try await MainActor.run {
            let descriptor = FetchDescriptor<SessionRecord>(
                predicate: #Predicate {
                    $0.title.localizedStandardContains(query)
                    || $0.rawText.localizedStandardContains(query)
                    || $0.refinedText.localizedStandardContains(query)
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try container.mainContext.fetch(descriptor).map { $0.toDomain() }
        }
    }
}
