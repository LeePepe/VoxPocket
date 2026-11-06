import Foundation
import Synchronization
import VoxCore

public final class LoadingFallbackTranscriptionCoordinator: SpeechSessionSource {
    private let primary: any SpeechSessionSource
    private let fallback: any SpeechSessionSource
    private let active = Mutex(false)
    private let capture = AsyncValueRelay<AudioCaptureState>(.idle)
    private let levels = AsyncValueRelay<Float>(0)
    private let tasks = Mutex<[Task<Void, Never>]>([])

    public init(primary: any SpeechSessionSource, fallback: any SpeechSessionSource) {
        self.primary = primary
        self.fallback = fallback
        bind(primary, fallback: false)
        bind(fallback, fallback: true)
    }
    deinit { tasks.withLock { $0 }.forEach { $0.cancel() } }
    private var current: any SpeechSessionSource { active.withLock { $0 } ? fallback : primary }
    public var primaryModelLoadingSource: (any ModelLoadingStateProviding)? { primary as? any ModelLoadingStateProviding }
    public var providerKind: ASRProviderType { current.providerKind }
    public var supportedLanguages: [Locale] { current.supportedLanguages }
    public var isActive: Bool { current.isActive }
    public var hasMicrophonePermission: Bool { current.hasMicrophonePermission }
    public var hasSpeechPermission: Bool { current.hasSpeechPermission }
    public func requestMicrophonePermission() async -> Bool { await current.requestMicrophonePermission() }
    public func requestSpeechPermission() async -> Bool { await current.requestSpeechPermission() }
    public func captureStates() -> AsyncStream<AudioCaptureState> { capture.stream() }
    public func audioLevels() -> AsyncStream<Float> { levels.stream() }
    public func startSession(language: Locale) async throws -> any SpeechSession {
        if let loading = primary as? any ModelLoadingStateProviding, loading.modelLoadingState == .idle {
            (primary as? any ModelPreloadControlling)?.startModelPreloadIfNeeded()
        }
        let useFallback = (primary as? any ModelLoadingStateProviding).map { $0.modelLoadingState != .ready } ?? false
        active.withLock { $0 = useFallback }
        return try await current.startSession(language: language)
    }
    private func bind(_ source: any SpeechSessionSource, fallback: Bool) {
        let states = source.captureStates()
        let audio = source.audioLevels()
        let stateTask = Task { [weak self] in
            for await state in states {
                guard let self, self.active.withLock({ $0 }) == fallback else { continue }
                self.capture.send(state)
                if state == .idle { self.levels.send(0) }
            }
        }
        let audioTask = Task { [weak self] in
            for await level in audio {
                guard let self, self.active.withLock({ $0 }) == fallback else { continue }
                self.levels.send(level)
            }
        }
        tasks.withLock { $0 += [stateTask, audioTask] }
    }
}
