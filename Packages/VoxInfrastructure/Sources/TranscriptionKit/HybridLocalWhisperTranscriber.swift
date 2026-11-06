import Foundation
import VoxCore

public final class HybridLocalWhisperTranscriber: SpeechAvailabilityProviding, SpeechSessionSource, MultiRecognizerSpeechSource,
    ModelLoadingStateProviding, ModelLoadingStartControlling, ModelPreloadControlling {
    private let core: HybridWhisperTranscriber
    private let engine: any LocalWhisperEngine
    private let loading = AsyncValueRelay<ModelLoadingState>(.idle)
    public let merger: (any TranscriptionMerger)?

    public init(config: LocalWhisperKitConfig = .default, logger: any VoxLogger = NoopVoxLogger(),
                merger: (any TranscriptionMerger)? = nil, storageLocations: VoxStorageLocations) {
        let engine = SharedLocalWhisperEngineHandle(config: config, logger: logger, storageLocations: storageLocations)
        self.engine = engine
        self.merger = merger
        core = HybridWhisperTranscriber(
            recorder: MicrophoneRecorder(logger: logger, storageLocations: storageLocations),
            speechRecognizer: SystemSpeechRecognizer(locale: Locale(identifier: "zh-Hans")),
            speechAuthorizationProvider: SystemSpeechAuthorizationProvider(),
            whisperEngine: LocalWhisperBatchAdapter(engine: engine, config: config),
            realtimeSessionMaker: DefaultRealtimeSessionMaker(), logger: logger, merger: merger,
            storageLocations: storageLocations)
        if config.preloadOnStart { startModelPreloadIfNeeded() }
    }

    init(recorder: any AudioBufferSource, speechRecognizer: any SpeechRecognizing,
         speechAuthorizationProvider: any SpeechAuthorizationProviding, batchTranscriber: any BatchTranscribing,
         whisperEngine: any LocalWhisperEngine, config: LocalWhisperKitConfig = .default,
         logger: any VoxLogger = NoopVoxLogger(), merger: (any TranscriptionMerger)? = nil,
         storageLocations: VoxStorageLocations) {
        engine = whisperEngine
        self.merger = merger
        core = HybridWhisperTranscriber(recorder: recorder, speechRecognizer: speechRecognizer,
            speechAuthorizationProvider: speechAuthorizationProvider, whisperEngine: batchTranscriber,
            realtimeSessionMaker: DefaultRealtimeSessionMaker(), logger: logger, merger: merger,
            storageLocations: storageLocations)
    }

    public var isSpeechAvailable: Bool { core.isSpeechAvailable }
    public var providerKind: ASRProviderType { core.providerKind }
    public var supportedLanguages: [Locale] { core.supportedLanguages }
    public var isActive: Bool { core.isActive }
    public var hasMicrophonePermission: Bool { core.hasMicrophonePermission }
    public var hasSpeechPermission: Bool { core.hasSpeechPermission }
    public func requestMicrophonePermission() async -> Bool { await core.requestMicrophonePermission() }
    public func requestSpeechPermission() async -> Bool { await core.requestSpeechPermission() }
    public func captureStates() -> AsyncStream<AudioCaptureState> { core.captureStates() }
    public func audioLevels() -> AsyncStream<Float> { core.audioLevels() }
    public func startSession(language: Locale) async throws -> any SpeechSession { try await core.startSession(language: language) }
    public var modelLoadingState: ModelLoadingState { loading.value }
    public func modelLoadingStates() -> AsyncStream<ModelLoadingState> { loading.stream() }
    public var blocksRecordingUntilModelReady: Bool { false }
    public func startModelPreloadIfNeeded() {
        guard loading.value == .idle else { return }
        loading.send(.loading)
        Task { [engine, loading] in
            do {
                try await engine.prepare(onProgress: { loading.send(.downloading(progress: $0)) })
                loading.send(.ready)
            } catch { loading.send(.failed("Model preparation failed")) }
        }
    }
}
