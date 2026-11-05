import Combine
import Foundation
import Synchronization
import TranscriptionKit
import VoxCore

// Sendable: Combine subjects are thread-safe; tasks, sessions and command ordering are Mutex-owned.
public class CombineTranscriptionCoordinator: TranscriptionCoordinator, QuickRecordingReleaseControlling, @unchecked Sendable {
    public let core: any SpeechSessionSource
    private struct State {
        var session: (any SpeechSession)?
        var startup: Task<any SpeechSession, Error>?
        var starting = false
        var pendingStates: [AudioCaptureState] = []
        var queue: Task<Void, Never>?
        var pump: Task<Void, Never>?
        var observers: [Task<Void, Never>] = []
    }
    private let state = Mutex(State())
    private let live = PassthroughSubject<TranscriptionResult, Error>()
    private let final = PassthroughSubject<TranscriptionResult, Error>()
    fileprivate let capture = CurrentValueSubject<AudioCaptureState, Never>(.idle)
    private let levels = CurrentValueSubject<Float, Never>(0)
    private lazy var audio = CombineAudioCapture(coordinator: self)
    private lazy var speech = CombineSpeechRecognition(coordinator: self)

    public init(core: any SpeechSessionSource) {
        self.core = core
        let states = core.captureStates()
        let audio = core.audioLevels()
        let captureTask = Task { [weak self] in
            var initial = true
            for await value in states {
                if initial { initial = false; if value == .idle { continue } }
                guard let self else { return }
                let forward = self.state.withLock { state in
                    if state.starting { state.pendingStates.append(value); return false }
                    return state.session == nil
                }
                if forward { self.capture.send(value) }
            }
        }
        let levelTask = Task { [weak self] in
            var initial = true
            for await value in audio {
                if initial { initial = false; if value == 0 { continue } }
                guard let self else { return }
                let forward = self.state.withLock { !$0.starting && $0.session == nil }
                if forward { self.levels.send(value) }
            }
        }
        state.withLock { $0.observers = [captureTask, levelTask] }
    }
    deinit {
        let snapshot = state.withLock { ($0.queue, $0.pump, $0.observers, $0.startup) }
        snapshot.0?.cancel(); snapshot.1?.cancel(); snapshot.3?.cancel()
        snapshot.2.forEach { $0.cancel() }
    }
    public static func wrap(_ core: any SpeechSessionSource) -> CombineTranscriptionCoordinator {
        let multi = core is any MultiRecognizerSpeechSource
        let loading = core is any ModelLoadingStateProviding
        let start = core is any TranscriptionKit.ModelLoadingStartControlling
        switch (multi, loading, start) {
        case (true, true, true): return CombineMultiRecognizerLoadingStartCoordinator(core: core)
        case (true, true, false): return CombineMultiRecognizerLoadingCoordinator(core: core)
        case (true, false, false): return CombineMultiRecognizerCoordinator(core: core)
        case (false, true, true): return CombineLoadingStartCoordinator(core: core)
        case (false, true, false): return CombineLoadingCoordinator(core: core)
        case (false, false, true): return CombineStartCoordinator(core: core)
        case (true, false, true): return CombineMultiRecognizerStartCoordinator(core: core)
        case (false, false, false): return CombineTranscriptionCoordinator(core: core)
        }
    }
    public var audioCaptureService: any AudioCaptureService { audio }
    public var speechRecognitionService: any SpeechRecognitionService { speech }
    public var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { final.eraseToAnyPublisher() }
    public var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> { live.eraseToAnyPublisher() }
    public var audioLevelPublisher: AnyPublisher<Float, Never> { levels.eraseToAnyPublisher() }
    public var isTranscribing: Bool { core.isActive }
    public func start(language: Locale) async throws {
        state.withLock { $0.pump }?.cancel()
        state.withLock { $0.starting = true; $0.pendingStates = [] }
        let startup = Task { [core] in try await core.startSession(language: language) }
        state.withLock { $0.startup = startup }
        let session: any SpeechSession
        do {
            session = try await withTaskCancellationHandler { try await startup.value } onCancel: { startup.cancel() }
        } catch {
            let pending = state.withLock { state in
                state.startup = nil; state.starting = false; state.session = nil
                defer { state.pendingStates = [] }
                return state.pendingStates
            }
            pending.forEach { capture.send($0) }
            throw error
        }
        let events = session.events()
        let task = Task { [weak self] in
            do {
                for try await event in events {
                    guard !Task.isCancelled else { return }
                    self?.receive(event)
                }
            } catch {
                self?.capture.send(.error("语音识别失败，请重试。"))
            }
        }
        state.withLock { $0.session = session; $0.pump = task; $0.startup = nil; $0.starting = false; $0.pendingStates = [] }
    }
    private func receive(_ event: TranscriptionEvent) {
        switch event {
        case .partial(let result): live.send(result)
        case .final(let result): final.send(result)
        case .level(let value): levels.send(value)
        case .state(let value): capture.send(value)
        }
    }
    public func stop() async {
        let pending = state.withLock { ($0.queue, $0.session, $0.startup) }
        if let startup = pending.2 {
            startup.cancel()
            if case .success(let session) = await startup.result { await session.stop() }
            return
        }
        await pending.0?.value
        await pending.1?.stop()
    }
    public func pause() { enqueue(pause: true) }
    public func resume() { enqueue(pause: false) }
    private func enqueue(pause: Bool) {
        state.withLock { state in
            let previous = state.queue
            let session = state.session
            state.queue = Task {
                await previous?.value
                guard !Task.isCancelled else { return }
                if pause { await session?.pause() } else { await session?.resume() }
            }
        }
    }
    public func prepareQuickRecording() throws {
        guard let source = core as? any QuickRecordingReleaseControlling else { throw QuickRecordingReleaseError.unsupported }
        try source.prepareQuickRecording()
    }
    public func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        guard let source = core as? any QuickRecordingReleaseControlling else { throw QuickRecordingReleaseError.unsupported }
        return try source.freezeQuickRecordingRelease()
    }
    public func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        guard let source = core as? any QuickRecordingReleaseControlling else { throw QuickRecordingReleaseError.unsupported }
        try await source.completeQuickRecordingRelease(snapshot)
    }
}

// Sendable: subclass adds immutable capability forwarding only.
public class CombineMultiRecognizerCoordinator: CombineTranscriptionCoordinator, MultiRecognizerTranscriber, @unchecked Sendable {
    public var merger: (any TranscriptionMerger)? { (core as? any MultiRecognizerSpeechSource)?.merger }
}
// Sendable: model observer owns its thread-safe subjects and task lifetime.
public class CombineLoadingCoordinator: CombineTranscriptionCoordinator, ModelLoadingObservable, @unchecked Sendable {
    private let loading: CombineModelLoadingObservable
    public override init(core: any SpeechSessionSource) {
        loading = CombineModelLoadingObservable(source: core as! any ModelLoadingStateProviding)
        super.init(core: core)
    }
    public var modelLoadingState: ModelLoadingState { loading.modelLoadingState }
    public var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> { loading.modelLoadingStatePublisher }
}
// Sendable: subclass only forwards immutable core capabilities.
public class CombineLoadingStartCoordinator: CombineLoadingCoordinator, ModelLoadingStartControlling, @unchecked Sendable {
    public var blocksRecordingUntilModelReady: Bool { (core as! any ModelLoadingStartControlling).blocksRecordingUntilModelReady }
}
// Sendable: subclass only forwards immutable core capabilities.
public class CombineMultiRecognizerLoadingCoordinator: CombineLoadingCoordinator, MultiRecognizerTranscriber, @unchecked Sendable {
    public var merger: (any TranscriptionMerger)? { (core as? any MultiRecognizerSpeechSource)?.merger }
}
// Sendable: subclass only forwards immutable core capabilities.
public final class CombineMultiRecognizerLoadingStartCoordinator: CombineMultiRecognizerLoadingCoordinator, ModelLoadingStartControlling, @unchecked Sendable {
    public var blocksRecordingUntilModelReady: Bool { (core as! any ModelLoadingStartControlling).blocksRecordingUntilModelReady }
}
// Sendable: subclass only forwards immutable core capabilities.
public final class CombineStartCoordinator: CombineTranscriptionCoordinator, ModelLoadingStartControlling, @unchecked Sendable {
    public var blocksRecordingUntilModelReady: Bool { (core as! any ModelLoadingStartControlling).blocksRecordingUntilModelReady }
}
// Sendable: subclass only forwards immutable core capabilities.
public final class CombineMultiRecognizerStartCoordinator: CombineMultiRecognizerCoordinator, ModelLoadingStartControlling, @unchecked Sendable {
    public var blocksRecordingUntilModelReady: Bool { (core as! any ModelLoadingStartControlling).blocksRecordingUntilModelReady }
}

// Sendable: subject operations are thread-safe; task is retained immutably after construction.
public final class CombineModelLoadingObservable: ModelLoadingObservable, @unchecked Sendable {
    private let source: any ModelLoadingStateProviding
    private let subject: CurrentValueSubject<ModelLoadingState, Never>
    private let task: Task<Void, Never>
    public init(source: any ModelLoadingStateProviding) {
        self.source = source
        let subject = CurrentValueSubject<ModelLoadingState, Never>(source.modelLoadingState)
        self.subject = subject
        let states = source.modelLoadingStates()
        task = Task { for await value in states { subject.send(value) } }
    }
    deinit { task.cancel() }
    public var modelLoadingState: ModelLoadingState { source.modelLoadingState }
    public var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> { subject.eraseToAnyPublisher() }
}

// Sendable: weak coordinator reference is immutable; its mutable state is Mutex-owned.
private final class CombineAudioCapture: AudioCaptureService, @unchecked Sendable {
    private weak var coordinator: CombineTranscriptionCoordinator?
    init(coordinator: CombineTranscriptionCoordinator) { self.coordinator = coordinator }
    var state: AudioCaptureState { coordinator?.capture.value ?? .idle }
    var statePublisher: AnyPublisher<AudioCaptureState, Never> { coordinator?.capture.eraseToAnyPublisher() ?? Just(.idle).eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { coordinator?.audioLevelPublisher ?? Just(0).eraseToAnyPublisher() }
    var hasPermission: Bool { coordinator?.core.hasMicrophonePermission ?? false }
    func requestPermission() async -> Bool { await coordinator?.core.requestMicrophonePermission() ?? false }
    func startCapture() async throws {}
    func stopCapture() async { await coordinator?.stop() }
    func pauseCapture() { coordinator?.pause() }
    func resumeCapture() { coordinator?.resume() }
}
// Sendable: weak coordinator reference is immutable; its mutable state is Mutex-owned.
private final class CombineSpeechRecognition: SpeechRecognitionService, @unchecked Sendable {
    private weak var coordinator: CombineTranscriptionCoordinator?
    init(coordinator: CombineTranscriptionCoordinator) { self.coordinator = coordinator }
    var providerType: ASRProviderType { coordinator?.core.providerKind ?? .custom }
    var resultPublisher: AnyPublisher<TranscriptionResult, Error> { coordinator!.liveResultPublisher }
    var supportedLanguages: [Locale] { coordinator?.core.supportedLanguages ?? [] }
    func requestPermission() async -> Bool { await coordinator?.core.requestSpeechPermission() ?? false }
    func checkAvailability() async -> Bool { (coordinator?.core as? any SpeechAvailabilityProviding)?.isSpeechAvailable ?? coordinator?.core.hasSpeechPermission ?? false }
    func startRecognition(language: Locale) async throws {}
    func stopRecognition() async { await coordinator?.stop() }
}
