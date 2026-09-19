import Combine
import Foundation
import Synchronization

/// Combine 桥接需要 unchecked Sendable；所有跨任务状态和订阅由 Mutex 保护。
/// 每次 start 读取一次选择，录音/收尾期间固定同一引擎，订阅方无需重新绑定。
public final class DefaultSelectableTranscriptionCoordinator: TranscriptionCoordinator,
    AudioCaptureService, SpeechRecognitionService, @unchecked Sendable {
    /// Combine 的取消令牌桥接；数组不可变，只允许取消，不暴露非 Sendable 令牌。
    private final class Subscriptions: @unchecked Sendable {
        private let values: [AnyCancellable]
        init(_ values: [AnyCancellable]) { self.values = values }
        func cancel() { values.forEach { $0.cancel() } }
    }
    private struct State {
        enum Phase { case idle, starting, recording, stopping }
        var phase: Phase = .idle
        var id = UUID()
        var active: (any TranscriptionCoordinator)?
        var startup: Task<Void, Error>?
        var subscriptions: Subscriptions?
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
        let task = try stateLock.withLock { state in
            guard state.phase == .idle else { throw RealtimeTranscriptionError.protocolRejected }
            state.phase = .starting
            let id = UUID(); state.id = id
            let task = Task { try await self.startSession(id: id, language: language) }
            state.startup = task
            return task
        }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func startSession(id: UUID, language: Locale) async throws {
        var coordinator: (any TranscriptionCoordinator)?
        do {
            let chosen = try await factory()
            coordinator = chosen
            try Task.checkCancellation()
            stateLock.withLock { $0.active = chosen }
            let subscriptions = bind(chosen, id: id)
            stateLock.withLock { $0.subscriptions = subscriptions }
            try await chosen.start(language: language)
            try Task.checkCancellation()
            stateLock.withLock { $0.phase = .recording; $0.startup = nil }
        } catch {
            await coordinator?.stop()
            clear(id)
            throw error
        }
    }

    public func stop() async {
        let snapshot = stateLock.withLock { state -> (Task<Void, Error>?, (any TranscriptionCoordinator)?, UUID) in
            switch state.phase {
            case .starting: return (state.startup, nil, state.id)
            case .recording:
                state.phase = .stopping
                return (nil, state.active, state.id)
            case .idle, .stopping: return (nil, nil, state.id)
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
            if let active { await active.stop(); clear(snapshot.2) }
        } else if let active = snapshot.1 {
            await active.stop()
            clear(snapshot.2)
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
        stateLock.withLock { $0.id == id && $0.phase != .idle }
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

    private func clear(_ id: UUID) {
        let result = stateLock.withLock { state -> (Bool, Subscriptions?) in
            guard state.id == id else { return (false, nil) }
            let subscriptions = state.subscriptions
            state = State()
            return (true, subscriptions)
        }
        guard result.0 else { return }
        result.1?.cancel()
        levels.send(0); capture.send(.idle)
    }
}
