import Foundation
import Combine
import Synchronization
import CoreModels

public protocol VoiceCaptureRepository: AnyObject, Sendable {
    func fetchAll() async throws -> [VoiceCapture]
    func fetch(by id: UUID) async throws -> VoiceCapture?
    func save(_ capture: VoiceCapture) async throws
    func delete(by id: UUID) async throws
    func observe() -> AnyPublisher<[VoiceCapture], Never>
}

public protocol VoiceTodoRepository: AnyObject, Sendable {
    func fetchAll() async throws -> [VoiceTodo]
    func fetch(by id: UUID) async throws -> VoiceTodo?
    func save(_ todo: VoiceTodo) async throws
    func update(id: UUID, transform: @Sendable (VoiceTodo) -> VoiceTodo?) async throws -> VoiceTodo?
    func delete(by id: UUID) async throws
    func observe() -> AnyPublisher<[VoiceTodo], Never>
}

public extension VoiceTodoRepository {
    func update(id: UUID, transform: @Sendable (VoiceTodo) -> VoiceTodo?) async throws -> VoiceTodo? {
        guard let current = try await fetch(by: id), let updated = transform(current) else {
            return nil
        }
        try await save(updated)
        return updated
    }
}

public protocol CloudSyncTransport: Sendable {
    func saveCaptureMetadata(_ data: Data) async throws
    func saveTodoMetadata(_ data: Data) async throws
    func captureMetadata() async throws -> Data?
    func todoMetadata() async throws -> Data?
}

public actor InMemoryCloudSyncTransport: CloudSyncTransport {
    private var captureData: Data?
    private var todoData: Data?
    public init() {}
    public func saveCaptureMetadata(_ data: Data) async throws { captureData = data }
    public func saveTodoMetadata(_ data: Data) async throws { todoData = data }
    public func captureMetadata() async throws -> Data? { captureData }
    public func todoMetadata() async throws -> Data? { todoData }
}

public final class UbiquitousKeyValueCloudSyncTransport: CloudSyncTransport, Sendable {
    private let directoryURL: URL
    private let captureURL: URL
    private let todoURL: URL

    public init(directoryURL: URL? = nil, store: UserDefaults? = nil, useICloud: Bool = true) {
        let base = directoryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VoxPocket/SyncMetadata", isDirectory: true)
        self.directoryURL = base
        self.captureURL = base.appendingPathComponent("capture-sync-metadata.json")
        self.todoURL = base.appendingPathComponent("todo-sync-metadata.json")
    }

    public func saveCaptureMetadata(_ data: Data) async throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: captureURL, options: .atomic)
    }
    public func saveTodoMetadata(_ data: Data) async throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: todoURL, options: .atomic)
    }
    public func captureMetadata() async throws -> Data? { try? Data(contentsOf: captureURL) }
    public func todoMetadata() async throws -> Data? { try? Data(contentsOf: todoURL) }
}

private actor AsyncMutationSerializer {
    private var tail: Task<Void, Never>?

    func enqueue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, any Error> {
            _ = await previous?.value
            return try await operation()
        }
        tail = Task {
            _ = try? await task.value
        }
        return try await task.value
    }
}

private struct CaptureStoreState: Sendable { var values: [UUID: VoiceCapture] = [:] }
private struct TodoStoreState: Sendable {
    var values: [UUID: VoiceTodo] = [:]
}

// Sendable: Combine CurrentValueSubject is bridged while mutable dictionary state is guarded by Mutex<CaptureStoreState>.
public final class DefaultVoiceCaptureRepository: VoiceCaptureRepository, @unchecked Sendable {
    private let state = Mutex(CaptureStoreState())
    private let subject = CurrentValueSubject<[VoiceCapture], Never>([])
    private let fileURL: URL?
    private let cloud: CloudSyncTransport?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directoryURL: URL? = nil, cloudSync: CloudSyncTransport? = nil) {
        self.fileURL = directoryURL?.appendingPathComponent("voice-captures.json")
        self.cloud = cloudSync
        load()
    }

    public func fetchAll() async throws -> [VoiceCapture] { state.withLock { sorted($0.values.values) } }
    public func fetch(by id: UUID) async throws -> VoiceCapture? { state.withLock { $0.values[id] } }
    public func save(_ capture: VoiceCapture) async throws {
        let values = state.withLock { state -> [VoiceCapture] in state.values[capture.id] = capture; return sorted(state.values.values) }
        try persist(values)
        subject.send(values)
        if let cloud { try await cloud.saveCaptureMetadata(encoder.encode(values.map { $0.sanitizedForCloudSync() })) }
    }
    public func delete(by id: UUID) async throws { let values = state.withLock { state -> [VoiceCapture] in state.values.removeValue(forKey: id); return sorted(state.values.values) }; try persist(values); subject.send(values) }
    public func observe() -> AnyPublisher<[VoiceCapture], Never> { subject.eraseToAnyPublisher() }

    private func sorted(_ values: Dictionary<UUID, VoiceCapture>.Values) -> [VoiceCapture] { values.sorted { $0.updatedAt > $1.updatedAt } }
    private func persist(_ values: [VoiceCapture]) throws { guard let fileURL else { return }; try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); try encoder.encode(values).write(to: fileURL, options: .atomic) }
    private func load() { guard let fileURL, let data = try? Data(contentsOf: fileURL), let values = try? decoder.decode([VoiceCapture].self, from: data) else { return }; let sortedValues = sorted(Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) }).values); state.withLock { $0.values = Dictionary(uniqueKeysWithValues: sortedValues.map { ($0.id, $0) }) }; subject.send(sortedValues) }
}

// Sendable: Combine CurrentValueSubject is bridged while mutable dictionary state, persistence, publication, and cloud writes are serialized by Mutex<TodoStoreState> and AsyncMutationSerializer.
public final class DefaultVoiceTodoRepository: VoiceTodoRepository, @unchecked Sendable {
    private let state = Mutex(TodoStoreState())
    private let cloudSerializer = AsyncMutationSerializer()
    private let subject = CurrentValueSubject<[VoiceTodo], Never>([])
    private let fileURL: URL?
    private let cloud: CloudSyncTransport?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directoryURL: URL? = nil, cloudSync: CloudSyncTransport? = nil) { self.fileURL = directoryURL?.appendingPathComponent("voice-todos.json"); self.cloud = cloudSync; load() }
    public func fetchAll() async throws -> [VoiceTodo] { state.withLock { $0.values.values.sorted { $0.updatedAt > $1.updatedAt } } }
    public func fetch(by id: UUID) async throws -> VoiceTodo? { state.withLock { $0.values[id] } }
    public func save(_ todo: VoiceTodo) async throws {
        let sanitizedData = try state.withLock { state -> Data in
            state.values[todo.id] = todo
            let values = state.values.values.sorted { $0.updatedAt > $1.updatedAt }
            try persist(values)
            subject.send(values)
            return try encoder.encode(values.map { $0.sanitizedForCloudSync() })
        }
        try await flushLatestCloudMetadata(fallbackData: sanitizedData)
    }
    public func update(id: UUID, transform: @Sendable (VoiceTodo) -> VoiceTodo?) async throws -> VoiceTodo? {
        let result = try state.withLock { state -> (updated: VoiceTodo, sanitizedData: Data)? in
            guard let current = state.values[id], let updated = transform(current) else { return nil }
            state.values[id] = updated
            let all = state.values.values.sorted { $0.updatedAt > $1.updatedAt }
            try persist(all)
            subject.send(all)
            let data = try encoder.encode(all.map { $0.sanitizedForCloudSync() })
            return (updated, data)
        }
        guard let result else { return nil }
        try await flushLatestCloudMetadata(fallbackData: result.sanitizedData)
        return result.updated
    }
    public func delete(by id: UUID) async throws {
        let sanitizedData = try state.withLock { state -> Data in
            state.values.removeValue(forKey: id)
            let values = state.values.values.sorted { $0.updatedAt > $1.updatedAt }
            try persist(values)
            subject.send(values)
            return try encoder.encode(values.map { $0.sanitizedForCloudSync() })
        }
        try await flushLatestCloudMetadata(fallbackData: sanitizedData)
    }
    public func observe() -> AnyPublisher<[VoiceTodo], Never> { subject.eraseToAnyPublisher() }
    private func flushLatestCloudMetadata(fallbackData: Data) async throws {
        guard let cloud else { return }
        try await cloudSerializer.enqueue { [self] in
            let currentData = state.withLock { state -> Data? in
                let all = state.values.values.sorted { $0.updatedAt > $1.updatedAt }
                return try? encoder.encode(all.map { $0.sanitizedForCloudSync() })
            } ?? fallbackData
            try await cloud.saveTodoMetadata(currentData)
        }
    }
    private func persist(_ values: [VoiceTodo]) throws { guard let fileURL else { return }; try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); try encoder.encode(values).write(to: fileURL, options: .atomic) }
    private func load() { guard let fileURL, let data = try? Data(contentsOf: fileURL), let values = try? decoder.decode([VoiceTodo].self, from: data) else { return }; let sortedValues = values.sorted { $0.updatedAt > $1.updatedAt }; state.withLock { $0.values = Dictionary(uniqueKeysWithValues: sortedValues.map { ($0.id, $0) }) }; subject.send(sortedValues) }
}
