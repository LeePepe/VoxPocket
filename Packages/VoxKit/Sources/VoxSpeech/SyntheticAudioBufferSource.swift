import VoxCore
import AVFoundation
import Foundation
import Synchronization

/// Deterministic capture double for tests; it never touches microphone hardware or disk.
public final class SyntheticAudioBufferSource: AudioBufferSource, Sendable {
    private let stateSubject = AsyncValueRelay<AudioCaptureState>(.idle)
    private let levelSubject = AsyncValueRelay<Float>(0)
    private let handler = Mutex<PCMBufferConsumer?>(nil)
    public init() {}
    public func audioLevels() -> AsyncStream<Float> { levelSubject.stream() }
    public func captureStates() -> AsyncStream<AudioCaptureState> { stateSubject.stream() }
    public var state: AudioCaptureState { stateSubject.value }
    public var hasPermission: Bool { true }
    public func requestPermission() async -> Bool { true }
    package func start(bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws {
        handler.withLock { $0 = bufferHandler.map(PCMBufferConsumer.init) }
        stateSubject.send(.recording)
    }
    package func startIfAllowed(shouldStart: @escaping @Sendable () -> Bool, bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws {
        guard shouldStart() else { throw CancellationError() }
        try await start(bufferHandler: bufferHandler)
    }
    public func pause() { stateSubject.send(.paused) }
    public func resume() { stateSubject.send(.recording) }
    @discardableResult public func stop() -> URL? { handler.withLock { $0 = nil }; stateSubject.send(.idle); return nil }
    public func emit(_ buffer: AVAudioPCMBuffer, level: Float = 0) {
        levelSubject.send(level)
        handler.withLock { $0 }?.consume(buffer)
    }
}

private struct PCMBufferConsumer: @unchecked Sendable { // Sendable: the immutable consumer is invoked synchronously at the Apple PCM boundary, like an audio tap.
    let consume: (AVAudioPCMBuffer) -> Void
}
