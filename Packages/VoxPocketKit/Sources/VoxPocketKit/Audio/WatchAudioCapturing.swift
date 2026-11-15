import Foundation

public protocol WatchAudioCapturing: Sendable {
    func start(captureID: UUID) async throws
    func stop() async throws -> WatchAudioCapture
    func cancel() async
    func levels(for captureID: UUID) async -> AsyncThrowingStream<WatchAudioLevel, Error>
}

public struct WatchAudioRecordingConfiguration: Sendable, Equatable {
    public let sampleRate: Double = 16_000
    public let channels: Int = 1
    public let bitRate: Int = 32_000
    public let format: String = "aac"
    public init() {}
}

public protocol WatchAudioRecorderBackend: Sendable {
    func requestPermission() async -> Bool
    func start(url: URL, configuration: WatchAudioRecordingConfiguration) throws
    func stop() throws
    func cancel()
    func currentPower() throws -> Float
}

public actor WatchAudioCaptureService: WatchAudioCapturing {
    private let storageURL: URL
    private let backend: any WatchAudioRecorderBackend
    private let maximumDuration: TimeInterval
    private var activeID: UUID?
    private var startedAt: ContinuousClock.Instant?
    private var completed: WatchAudioCapture?
    private var continuations: [UUID: AsyncThrowingStream<WatchAudioLevel, Error>.Continuation] = [:]
    private var meterTask: Task<Void, Never>?

    public init(storageURL: URL, backend: any WatchAudioRecorderBackend = DefaultWatchAudioRecorderBackend(), maximumDuration: TimeInterval = WatchCaptureMetadata.maxDuration) {
        self.storageURL = storageURL; self.backend = backend
        self.maximumDuration = maximumDuration.isFinite ? min(max(maximumDuration, 0.1), WatchCaptureMetadata.maxDuration) : WatchCaptureMetadata.maxDuration
    }

    public func start(captureID: UUID) async throws {
        guard activeID == nil else { throw WatchCaptureError.alreadyRecording }
        activeID = captureID
        var backendStarted = false
        do {
            guard await backend.requestPermission() else { throw WatchCaptureError.permissionDenied }
            try Task.checkCancellation()
            guard activeID == captureID else { throw CancellationError() }
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            let url = storageURL.appendingPathComponent("\(captureID.uuidString).m4a")
            guard !FileManager.default.fileExists(atPath: url.path) else { throw WatchCaptureError.invalidAudioFile }
            backendStarted = true
            try backend.start(url: url, configuration: WatchAudioRecordingConfiguration())
            completed = nil; startedAt = .now
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                    guard let self, await self.sample() else { break }
                }
            }
        } catch {
            if activeID == captureID {
                if backendStarted { backend.cancel() }
                reset(error: error)
            }
            throw error
        }
    }

    public func stop() async throws -> WatchAudioCapture {
        if let completed, activeID == nil { self.completed = nil; return completed }
        guard let id = activeID, startedAt != nil else { throw WatchCaptureError.notRecording }
        let capture = WatchAudioCapture(captureID: id, fileURL: storageURL.appendingPathComponent("\(id.uuidString).m4a"), duration: elapsed)
        do {
            try backend.stop(); try WatchAudioFileValidation.validate(capture.fileURL)
            reset(); return capture
        } catch { reset(error: WatchCaptureError.captureFailed); throw WatchCaptureError.captureFailed }
    }
    public func cancel() async { backend.cancel(); completed = nil; reset() }
    private var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        let value = startedAt.duration(to: .now).components
        return min(maximumDuration, max(0, Double(value.seconds) + Double(value.attoseconds) / 1e18))
    }
    private func sample() -> Bool {
        guard let id = activeID else { return false }
        do {
            let value = try backend.currentPower()
            continuations[id]?.yield(WatchAudioLevel(captureID: id, normalizedLevel: value, elapsed: elapsed))
            if elapsed >= maximumDuration {
                completed = WatchAudioCapture(captureID: id, fileURL: storageURL.appendingPathComponent("\(id.uuidString).m4a"), duration: elapsed)
                try backend.stop(); reset(); return false
            }
            return true
        } catch { try? backend.stop(); reset(error: WatchCaptureError.captureFailed); return false }
    }
    public func levels(for captureID: UUID) async -> AsyncThrowingStream<WatchAudioLevel, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: WatchAudioLevel.self)
        guard activeID == captureID else { continuation.finish(); return stream }
        continuations[captureID]?.finish(); continuations[captureID] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeContinuation(captureID) } }
        return stream
    }
    private func removeContinuation(_ id: UUID) { continuations.removeValue(forKey: id) }
    private func reset(error: Error? = nil) {
        if let id = activeID { continuations.removeValue(forKey: id)?.finish(throwing: error) }
        activeID = nil; startedAt = nil; meterTask?.cancel(); meterTask = nil
    }
    deinit { meterTask?.cancel() }
}

