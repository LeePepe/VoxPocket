import Foundation
import Synchronization
import VoxCore

package final class SpeechSessionRelay: Sendable {
    private struct State {
        var id = UUID()
        var continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation?
    }
    private let state = Mutex(State())
    func open() -> (UUID, AsyncThrowingStream<TranscriptionEvent, Error>) {
        let pair = AsyncThrowingStream<TranscriptionEvent, Error>.makeStream()
        let id = UUID()
        let old = state.withLock { state in
            let old = state.continuation
            state = State(id: id, continuation: pair.continuation)
            return old
        }
        old?.finish()
        return (id, pair.stream)
    }
    func isCurrent(_ id: UUID) -> Bool { state.withLock { $0.id == id && $0.continuation != nil } }
    func send(_ event: TranscriptionEvent) { state.withLock { $0.continuation }?.yield(event) }
    func send(_ event: TranscriptionEvent, id: UUID) {
        let current = state.withLock { state in state.id == id ? state.continuation : nil }
        current?.yield(event)
    }
    func finish(id: UUID? = nil, throwing error: (any Error)? = nil) {
        let current = state.withLock { state -> AsyncThrowingStream<TranscriptionEvent, Error>.Continuation? in
            guard id == nil || state.id == id else { return nil }
            defer { state.continuation = nil }
            return state.continuation
        }
        current?.finish(throwing: error)
    }
}

protocol SessionDriving: SpeechSessionSource {
    var sessionRelay: SpeechSessionRelay { get }
    var finishesRelayOnStopReturn: Bool { get }
    func start(language: Locale) async throws
    func stop() async
    func pause() async
    func resume() async
    func captureDeviceStates() -> AsyncStream<AudioCaptureState>
    func interruptCapture() async
}

extension SessionDriving {
    var finishesRelayOnStopReturn: Bool { true }
    func captureDeviceStates() -> AsyncStream<AudioCaptureState> { captureStates() }
    func interruptCapture() async {
        await stop()
        sessionRelay.send(.state(.interrupted))
    }
    public func startSession(language: Locale) async throws -> any SpeechSession {
        if isActive { await stop() }
        let (id, stream) = sessionRelay.open()
        let session = DrivenSpeechSession(source: self, id: id, stream: stream, levels: audioLevels())
        do {
            try await start(language: language)
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled { await stop() }
            sessionRelay.finish(throwing: error)
            throw error
        }
        return session
    }
}

private final class DrivenSpeechSession: SpeechSession {
    private let source: any SessionDriving
    private let id: UUID
    private let stream: AsyncThrowingStream<TranscriptionEvent, Error>
    private let levels: Task<Void, Never>
    private let interruptions: Task<Void, Never>
    init(source: any SessionDriving, id: UUID, stream: AsyncThrowingStream<TranscriptionEvent, Error>, levels: AsyncStream<Float>) {
        self.source = source
        self.id = id
        self.stream = stream
        let deviceStates = source.captureDeviceStates()
        let levelsTask = Task { [relay = source.sessionRelay] in
            var initial = true
            for await level in levels {
                if initial { initial = false; continue }
                guard !Task.isCancelled, relay.isCurrent(id) else { return }
                relay.send(.level(level), id: id)
            }
        }
        self.levels = levelsTask
        self.interruptions = Task { [levelsTask] in
            for await state in deviceStates {
                guard !Task.isCancelled, source.sessionRelay.isCurrent(id) else { return }
                if state == .interrupted {
                    levelsTask.cancel()
                    await source.interruptCapture()
                    source.sessionRelay.finish(id: id)
                    return
                }
            }
        }
    }
    deinit { levels.cancel(); interruptions.cancel() }
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error> { stream }
    func pause() async { if source.sessionRelay.isCurrent(id) { await source.pause() } }
    func resume() async { if source.sessionRelay.isCurrent(id) { await source.resume() } }
    func stop() async {
        guard source.sessionRelay.isCurrent(id) else { return }
        levels.cancel()
        interruptions.cancel()
        await source.stop()
        if source.finishesRelayOnStopReturn { source.sessionRelay.finish(id: id) }
    }
    func cancel() async {
        guard source.sessionRelay.isCurrent(id) else { return }
        levels.cancel()
        interruptions.cancel()
        source.sessionRelay.finish(throwing: CancellationError())
        await source.stop()
    }
}
