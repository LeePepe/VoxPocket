import Combine
import Foundation
import Synchronization

/// Combine 桥接需要 unchecked Sendable；所有跨任务状态和订阅由 Mutex 保护。
/// 每次 start 读取一次选择，录音/收尾期间固定同一引擎，订阅方无需重新绑定。
public final class DefaultSelectableTranscriptionCoordinator: TranscriptionCoordinator,
    AudioCaptureService, SpeechRecognitionService, QuickRecordingReleaseControlling, @unchecked Sendable {
    /// Combine 的取消令牌桥接；数组不可变，只允许取消，不暴露非 Sendable 令牌。
    private final class Subscriptions: @unchecked Sendable {
        private let values: [AnyCancellable]
        init(_ values: [AnyCancellable]) { self.values = values }
        func cancel() { values.forEach { $0.cancel() } }
    }
    private struct State {
        enum Phase { case idle, prepared, starting, recording, stopping }
        var phase: Phase = .idle
        var id = UUID()
        var active: (any TranscriptionCoordinator)?
        var startup: Task<Void, Error>?
        var subscriptions: Subscriptions?
        var isQuick = false
        var release: QuickRecordingReleaseSnapshot?
        var sourceRelease: QuickRecordingReleaseSnapshot?
        var releaseClaimed = false
        var muted = false
    }
    private let stateLock = Mutex(State())
    private let factory: @Sendable () async throws -> any TranscriptionCoordinator
    private let permissions: any TranscriptionCoordinator
    private let live = PassthroughSubject<TranscriptionResult, Error>()
    private let final = PassthroughSubject<TranscriptionResult, Error>()
    private let levels = CurrentValueSubject<Float, Never>(0)
    private let capture = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    public init(permissionCoordinator: any TranscriptionCoordinator,
                factory: @escaping @Sendable () async throws -> any TranscriptionCoordinator) {
        permissions = permissionCoordinator
        self.factory = factory
    }

    public var audioCaptureService: any AudioCaptureService { self }
    public var speechRecognitionService: any SpeechRecognitionService { self }
    public var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> { live.eraseToAnyPublisher() }
    public var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { final.eraseToAnyPublisher() }
    public var audioLevelPublisher: AnyPublisher<Float, Never> { levels.eraseToAnyPublisher() }
    public var statePublisher: AnyPublisher<AudioCaptureState, Never> { capture.eraseToAnyPublisher() }
    public var state: AudioCaptureState { capture.value }
    public var resultPublisher: AnyPublisher<TranscriptionResult, Error> { liveResultPublisher }
    public var providerType: ASRProviderType { .custom }
    public var supportedLanguages: [Locale] { permissions.speechRecognitionService.supportedLanguages }
    public var hasPermission: Bool { permissions.audioCaptureService.hasPermission }
    public var isTranscribing: Bool { stateLock.withLock { $0.phase == .recording } }

    public func start(language: Locale) async throws {
        let prepared = try stateLock.withLock { state in
            guard state.phase == .idle || state.phase == .prepared else {
                throw RealtimeTranscriptionError.protocolRejected
            }
            guard state.release?.hasRecognizedSpeech != false else { throw CancellationError() }
            // 旧订阅在锁外取消，避免 Combine 取消回调重入同一把锁。
            let old = (state.active, state.subscriptions)
            state.active = nil; state.subscriptions = nil
            state.phase = .starting
            if !state.isQuick { state.id = UUID(); state.muted = false }
            let id = state.id
            let task = Task { try await self.startSession(id: id, language: language) }
            state.startup = task
            return (task, old)
        }
        prepared.1.1?.cancel()
        let task = prepared.0
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func startSession(id: UUID, language: Locale) async throws {
        var coordinator: (any TranscriptionCoordinator)?
        do {
            let chosen = try await factory()
            coordinator = chosen
            try Task.checkCancellation()
            try attach(chosen, id: id)
            let subscriptions = bind(chosen, id: id)
            stateLock.withLock { $0.subscriptions = subscriptions }
            try await chosen.start(language: language)
            try Task.checkCancellation()
            stateLock.withLock {
                guard $0.id == id else { return }
                $0.phase = .recording; $0.startup = nil
            }
        } catch {
            if stateLock.withLock({ $0.id == id && $0.isQuick }) {
                await failQuickStartup(id: id)
            } else {
                await coordinator?.stop()
                clear(id)
            }
            throw error
        }
    }

    private func attach(_ chosen: any TranscriptionCoordinator, id: UUID) throws {
        try stateLock.withLock { state in
            guard state.id == id, state.phase == .starting,
                  state.release?.hasRecognizedSpeech != false else { throw CancellationError() }
            if state.isQuick {
                guard let source = chosen as? any QuickRecordingReleaseControlling else {
                    throw QuickRecordingReleaseError.unsupported
                }
                try source.prepareQuickRecording()
            }
            state.active = chosen
        }
    }

    private func failQuickStartup(id: UUID) async {
        defer { clear(id) }
        let active = stateLock.withLock { state -> (any TranscriptionCoordinator)? in
            guard state.id == id else { return nil }
            state.startup = nil; state.phase = .stopping; state.muted = true
            return state.active
        }
        guard let source = active as? any QuickRecordingReleaseControlling,
              let frozen = try? source.freezeQuickRecordingRelease() else { return }
        let discard = QuickRecordingReleaseSnapshot(sessionID: frozen.sessionID, hasRecognizedSpeech: false)
        try? await source.completeQuickRecordingRelease(discard)
    }

    public func prepareQuickRecording() throws {
        let old = try stateLock.withLock { state in
            guard state.phase == .idle else { throw RealtimeTranscriptionError.protocolRejected }
            let old = state.subscriptions
            state = State()
            state.phase = .prepared; state.isQuick = true
            return old
        }
        old?.cancel()
    }

    public func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        try stateLock.withLock { state in
            guard state.isQuick else { throw QuickRecordingReleaseError.noPreparedSession }
            if let frozen = state.release { return frozen }
            let source = state.active as? any QuickRecordingReleaseControlling
            let sourceRelease = try source?.freezeQuickRecordingRelease()
            let frozen = QuickRecordingReleaseSnapshot(sessionID: state.id,
                                                       hasRecognizedSpeech: sourceRelease?.hasRecognizedSpeech == true)
            state.sourceRelease = sourceRelease; state.release = frozen
            state.muted = !frozen.hasRecognizedSpeech
            return frozen
        }
    }

    public func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        let pending = stateLock.withLock { state -> (Bool, Task<Void, Error>?) in
            guard state.id == snapshot.sessionID, let frozen = state.release, !state.releaseClaimed,
                  !snapshot.hasRecognizedSpeech || frozen.hasRecognizedSpeech else { return (false, nil) }
            state.releaseClaimed = true; state.phase = .stopping
            state.muted = !snapshot.hasRecognizedSpeech
            return (true, state.startup)
        }
        guard pending.0 else { return }
        defer { clear(snapshot.sessionID, keepResults: snapshot.hasRecognizedSpeech) }
        if !snapshot.hasRecognizedSpeech { pending.1?.cancel() }
        if let task = pending.1 { _ = await task.result }
        let source = stateLock.withLock { state in
            (state.active as? any QuickRecordingReleaseControlling, state.sourceRelease)
        }
        guard let capability = source.0, let frozen = source.1 else { return }
        try await capability.completeQuickRecordingRelease(.init(sessionID: frozen.sessionID,
                                                                 hasRecognizedSpeech: snapshot.hasRecognizedSpeech))
    }

    public func stop() async {
        let snapshot = stateLock.withLock { state -> (Task<Void, Error>?, (any TranscriptionCoordinator)?, UUID) in
            switch state.phase {
            case .starting: return (state.startup, nil, state.id)
            case .recording:
                state.phase = .stopping
                return (nil, state.active, state.id)
            case .prepared, .idle, .stopping: return (nil, nil, state.id)
            }
        }
        if let startup = snapshot.0 {
            startup.cancel()
            _ = await startup.result
            // start 可能恰好先完成；停止这一代，不能影响清理后新开的录音。
            let active = stateLock.withLock { state -> (any TranscriptionCoordinator)? in
                guard state.id == snapshot.2, state.phase == .recording else { return nil }
                state.phase = .stopping
                return state.active
            }
            if let active { await active.stop(); clear(snapshot.2, keepResults: true) }
        } else if let active = snapshot.1 {
            await active.stop()
            clear(snapshot.2, keepResults: true)
        }
    }

    public func pause() { stateLock.withLock { $0.active }?.pause() }
    public func resume() { stateLock.withLock { $0.active }?.resume() }
    public func pauseCapture() { pause() }
    public func resumeCapture() { resume() }
    public func startCapture() async throws {}
    public func stopCapture() async { await stop() }
    public func startRecognition(language: Locale) async throws {}
    public func stopRecognition() async { await stop() }
    public func checkAvailability() async -> Bool { true }
    public func requestPermission() async -> Bool {
        guard await permissions.audioCaptureService.requestPermission() else { return false }
        return await permissions.speechRecognitionService.requestPermission()
    }

    private func isCurrent(_ id: UUID) -> Bool {
        // Apple Speech.stop 返回后才可能发出终稿；保留这一代直到下一次 start。
        stateLock.withLock { $0.id == id && $0.active != nil && !$0.muted }
    }

    private func bind(_ chosen: any TranscriptionCoordinator, id: UUID) -> Subscriptions {
        let failed: @Sendable (Subscribers.Completion<Error>) -> Void = { [weak self] completion in
            guard let self, self.isCurrent(id), case .failure = completion else { return }
            // 错误经捕获状态传播；不能终结跨录音复用的 publisher，也不回显供应商正文。
            self.capture.send(.error("语音识别失败，请重试。"))
        }
        return Subscriptions([
            chosen.liveResultPublisher.sink(receiveCompletion: failed) { [weak self] value in
                guard let self, self.isCurrent(id) else { return }; self.live.send(value)
            },
            chosen.finalResultPublisher.sink(receiveCompletion: failed) { [weak self] value in
                guard let self, self.isCurrent(id) else { return }; self.final.send(value)
            },
            chosen.audioLevelPublisher.sink { [weak self] value in
                guard let self, self.isCurrent(id) else { return }; self.levels.send(value)
            },
            chosen.audioCaptureService.statePublisher.sink { [weak self] value in
                guard let self, self.isCurrent(id) else { return }; self.capture.send(value)
            }
        ])
    }

    private func clear(_ id: UUID, keepResults: Bool = false) {
        let result = stateLock.withLock { state -> (Bool, Subscriptions?, (any TranscriptionCoordinator)?) in
            guard state.id == id else { return (false, nil, nil) }
            state.phase = .idle; state.startup = nil; state.isQuick = false
            state.release = nil; state.sourceRelease = nil; state.releaseClaimed = false
            if keepResults { return (true, nil, nil) }
            let old = (state.subscriptions, state.active)
            state.subscriptions = nil; state.active = nil
            return (true, old.0, old.1)
        }
        guard result.0 else { return }
        result.1?.cancel()
        levels.send(0); capture.send(.idle)
    }
}
