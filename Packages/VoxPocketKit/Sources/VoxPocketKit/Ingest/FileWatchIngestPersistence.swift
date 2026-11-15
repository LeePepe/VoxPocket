import Foundation

public actor FileWatchIngestPersistence: WatchIngestPersistence {
    private struct State: Codable {
        var pending: [UUID: WatchCaptureMetadata] = [:]
        var completions: [UUID: WatchCaptureReceipt] = [:]
    }
    private struct LegacyState: Codable {
        let pending: [WatchCaptureMetadata]
        let completions: [WatchCaptureReceipt]
    }
    private let directory: URL
    private var state = State()
    private var loaded = false
    public init(directory: URL) { self.directory = directory }
    public func pending() throws -> [WatchCaptureMetadata] { try load(); return Array(state.pending.values) }
    public func completion(for captureID: UUID) throws -> WatchCaptureReceipt? { try load(); return state.completions[captureID] }
    public func savePending(_ metadata: WatchCaptureMetadata) throws {
        try load()
        if let old = state.pending[metadata.captureID], old != metadata { throw WatchCaptureError.invalidAudioFile }
        var next = state; next.pending[metadata.captureID] = metadata; try save(next)
    }
    public func removePending(captureID: UUID) throws { try load(); var next = state; next.pending.removeValue(forKey: captureID); try save(next) }
    public func saveCompletion(_ receipt: WatchCaptureReceipt) throws {
        guard receipt.isValid, case .todoAdded = receipt.status else { throw WatchCaptureError.captureFailed }
        try load(); var next = state; next.completions[receipt.captureID] = receipt; try save(next)
    }
    private func load() throws {
        guard !loaded else { return }
        let url = directory.appendingPathComponent("ingest.json")
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        } else {
            let legacyURL = directory.appendingPathComponent("watch-state.json")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                let legacy = try JSONDecoder().decode(LegacyState.self, from: Data(contentsOf: legacyURL))
                var migrated = State()
                for metadata in legacy.pending { migrated.pending[metadata.captureID] = metadata }
                for receipt in legacy.completions where receipt.isValid {
                    if case .todoAdded = receipt.status { migrated.completions[receipt.captureID] = receipt }
                }
                try save(migrated)
            }
        }
        loaded = true
    }
    private func save(_ next: State) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("ingest.json"), options: .atomic)
        state = next
    }
}
