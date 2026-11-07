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
    func delete(by id: UUID) async throws
    func observe() -> AnyPublisher<[VoiceTodo], Never>
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

public final class UbiquitousKeyValueCloudSyncTransport: CloudSyncTransport, @unchecked Sendable {
    private let ubiquitousStore: NSUbiquitousKeyValueStore?
    private let defaults: UserDefaults
    private let captureKey = "voxpocket.cloud.voiceCaptures"
    private let todoKey = "voxpocket.cloud.voiceTodos"

    public init(store: UserDefaults? = nil, useICloud: Bool = true) {
        self.ubiquitousStore = useICloud ? NSUbiquitousKeyValueStore.default : nil
        self.defaults = store ?? .standard
    }

    public func saveCaptureMetadata(_ data: Data) async throws { ubiquitousStore?.set(data, forKey: captureKey); defaults.set(data, forKey: captureKey) }
    public func saveTodoMetadata(_ data: Data) async throws { ubiquitousStore?.set(data, forKey: todoKey); defaults.set(data, forKey: todoKey) }
    public func captureMetadata() async throws -> Data? { ubiquitousStore?.data(forKey: captureKey) ?? defaults.data(forKey: captureKey) }
    public func todoMetadata() async throws -> Data? { ubiquitousStore?.data(forKey: todoKey) ?? defaults.data(forKey: todoKey) }
}

private struct CaptureStoreState: Sendable { var values: [UUID: VoiceCapture] = [:] }
private struct TodoStoreState: Sendable { var values: [UUID: VoiceTodo] = [:] }

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
        if let cloud { try await cloud.saveCaptureMetadata(encoder.encode(values.map { VoiceCapture(id: $0.id, mode: $0.mode, rawTranscript: $0.rawTranscript, refinedText: $0.refinedText, durationSeconds: $0.durationSeconds, deviceSource: $0.deviceSource, state: $0.state, linkedTodoID: $0.linkedTodoID, createdAt: $0.createdAt, updatedAt: $0.updatedAt) })) }
    }
    public func delete(by id: UUID) async throws { let values = state.withLock { state -> [VoiceCapture] in state.values.removeValue(forKey: id); return sorted(state.values.values) }; try persist(values); subject.send(values) }
    public func observe() -> AnyPublisher<[VoiceCapture], Never> { subject.eraseToAnyPublisher() }

    private func sorted(_ values: Dictionary<UUID, VoiceCapture>.Values) -> [VoiceCapture] { values.sorted { $0.updatedAt > $1.updatedAt } }
    private func persist(_ values: [VoiceCapture]) throws { guard let fileURL else { return }; try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); try encoder.encode(values).write(to: fileURL, options: .atomic) }
    private func load() { guard let fileURL, let data = try? Data(contentsOf: fileURL), let values = try? decoder.decode([VoiceCapture].self, from: data) else { return }; let sortedValues = sorted(Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) }).values); state.withLock { $0.values = Dictionary(uniqueKeysWithValues: sortedValues.map { ($0.id, $0) }) }; subject.send(sortedValues) }
}

public final class DefaultVoiceTodoRepository: VoiceTodoRepository, @unchecked Sendable {
    private let state = Mutex(TodoStoreState())
    private let subject = CurrentValueSubject<[VoiceTodo], Never>([])
    private let fileURL: URL?
    private let cloud: CloudSyncTransport?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directoryURL: URL? = nil, cloudSync: CloudSyncTransport? = nil) { self.fileURL = directoryURL?.appendingPathComponent("voice-todos.json"); self.cloud = cloudSync; load() }
    public func fetchAll() async throws -> [VoiceTodo] { state.withLock { $0.values.values.sorted { $0.updatedAt > $1.updatedAt } } }
    public func fetch(by id: UUID) async throws -> VoiceTodo? { state.withLock { $0.values[id] } }
    public func save(_ todo: VoiceTodo) async throws {
        let values = state.withLock { state -> [VoiceTodo] in state.values[todo.id] = todo; return state.values.values.sorted { $0.updatedAt > $1.updatedAt } }
        try persist(values); subject.send(values)
        if let cloud { try await cloud.saveTodoMetadata(encoder.encode(values.map { $0.sanitizedForCloudSync() })) }
    }
    public func delete(by id: UUID) async throws { let values = state.withLock { state -> [VoiceTodo] in state.values.removeValue(forKey: id); return state.values.values.sorted { $0.updatedAt > $1.updatedAt } }; try persist(values); subject.send(values) }
    public func observe() -> AnyPublisher<[VoiceTodo], Never> { subject.eraseToAnyPublisher() }
    private func persist(_ values: [VoiceTodo]) throws { guard let fileURL else { return }; try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); try encoder.encode(values).write(to: fileURL, options: .atomic) }
    private func load() { guard let fileURL, let data = try? Data(contentsOf: fileURL), let values = try? decoder.decode([VoiceTodo].self, from: data) else { return }; let sortedValues = values.sorted { $0.updatedAt > $1.updatedAt }; state.withLock { $0.values = Dictionary(uniqueKeysWithValues: sortedValues.map { ($0.id, $0) }) }; subject.send(sortedValues) }
}
