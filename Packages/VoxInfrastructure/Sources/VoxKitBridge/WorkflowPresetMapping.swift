import Foundation
import Combine
import Synchronization
import VoxCore
import VoxSpeech
import VoxLLM
import VoxRefine
import VoxWorkflow
import Preferences

public struct StagePresetMapping: Sendable {
    public init() {}

    public static func preset(
        settings: StageModelSettings,
        batchConfigured: Bool,
        realtimeConfigured: Bool,
        azureTextConfigured: Bool
    ) -> Preset {
        let speech: String
        if settings.speech == .appleSpeech || !batchConfigured {
            speech = "appleSpeech"
        } else if settings.speech == .realtime && realtimeConfigured {
            speech = "realtime"
        } else {
            speech = "batch"
        }
        return Preset.default.overriding([
            "speech": speech,
            "speech.merger": "false",
            "analysis.intent": settings.intent.rawValue,
            "analysis.entities": settings.intent.rawValue,
            "analysis.tags": settings.intent.rawValue,
            "analysis.params": settings.intent.rawValue,
            "analysis.tone": settings.tone.rawValue,
            "analysis.skip": settings.skipAnalysis ? "true" : "false",
            "refine.provider": settings.refinement.rawValue
        ])
    }

    public static func makePreset(
        settings: StageModelSettings,
        batchConfigured: Bool,
        realtimeConfigured: Bool,
        azureTextConfigured: Bool
    ) -> Preset {
        preset(settings: settings, batchConfigured: batchConfigured,
               realtimeConfigured: realtimeConfigured, azureTextConfigured: azureTextConfigured)
    }

    public static func exportedPipeline(
        settings: StageModelSettings,
        batchConfigured: Bool,
        realtimeConfigured: Bool,
        azureTextConfigured: Bool
    ) -> WorkflowPipelineSnapshot {
        preset(settings: settings, batchConfigured: batchConfigured,
               realtimeConfigured: realtimeConfigured, azureTextConfigured: azureTextConfigured)
            .exportedPipeline(batchConfigured: batchConfigured, realtimeConfigured: realtimeConfigured,
                              azureTextConfigured: azureTextConfigured)
    }

}

public struct IOSPresetMapping: Sendable {
    public let batchConfigured: Bool
    public let realtimeConfigured: Bool
    public let azureTextConfigured: Bool
    public let speech: SpeechModelSelection
    public let provider: LLMProviderType
    public let skipContentAnalysis: Bool

    public init(
        batchConfigured: Bool,
        realtimeConfigured: Bool = false,
        azureTextConfigured: Bool,
        speech: SpeechModelSelection = .batch,
        provider: LLMProviderType = .azureFoundry,
        skipContentAnalysis: Bool = true
    ) {
        self.batchConfigured = batchConfigured
        self.realtimeConfigured = realtimeConfigured
        self.azureTextConfigured = azureTextConfigured
        self.speech = speech
        self.provider = provider
        self.skipContentAnalysis = true
    }

    public var preset: Preset {
        Self.preset(batchConfigured: batchConfigured, realtimeConfigured: realtimeConfigured,
                    azureTextConfigured: azureTextConfigured, speech: speech,
                    provider: provider, skipContentAnalysis: true)
    }

    public static func preset(
        batchConfigured: Bool,
        realtimeConfigured: Bool = false,
        azureTextConfigured: Bool,
        speech: SpeechModelSelection = .batch,
        provider: LLMProviderType = .azureFoundry,
        skipContentAnalysis: Bool = true
    ) -> Preset {
        let resolvedSpeech: String
        if speech == .appleSpeech || !batchConfigured {
            resolvedSpeech = "appleSpeech"
        } else if speech == .realtime && realtimeConfigured {
            resolvedSpeech = "realtime"
        } else {
            resolvedSpeech = "batch"
        }
        let base = (resolvedSpeech == "appleSpeech") ? Preset.appleSpeech : Preset.hybridAzure
        return base.overriding([
            "speech": resolvedSpeech,
            "speech.merger": "false",
            "analysis.intent": LLMProviderType.appleIntelligence.rawValue,
            "analysis.entities": provider.rawValue,
            "analysis.tags": provider.rawValue,
            "analysis.params": provider.rawValue,
            "analysis.tone": LLMProviderType.appleIntelligence.rawValue,
            "analysis.skip": "true",
            "refine.provider": provider.rawValue
        ])
    }

    public static func makePreset(
        batchConfigured: Bool,
        realtimeConfigured: Bool = false,
        azureTextConfigured: Bool,
        speech: SpeechModelSelection = .batch,
        provider: LLMProviderType = .azureFoundry,
        skipContentAnalysis: Bool = true
    ) -> Preset {
        preset(batchConfigured: batchConfigured, realtimeConfigured: realtimeConfigured,
               azureTextConfigured: azureTextConfigured, speech: speech,
               provider: provider, skipContentAnalysis: true)
    }

    public func exportedPipeline() -> WorkflowPipelineSnapshot {
        preset.exportedPipeline(batchConfigured: batchConfigured, realtimeConfigured: realtimeConfigured,
                                azureTextConfigured: azureTextConfigured)
    }

}

@MainActor
public final class IOSPresetPreferenceBinding {
    public private(set) var currentProvider: LLMProviderType
    public private(set) var currentSpeech: SpeechModelSelection
    public private(set) var currentRealtimeDeployment: String = ""
    public private(set) var currentStreamModel: RealtimeStreamModelKind = .gptRealtime
    public private(set) var currentGPTRealtimeDeployment: String = ""
    public private(set) var currentMAIRealtimeDeployment: String = ""
    public private(set) var preset: Preset
    public var activePreset: Preset { preset }
    public var currentSettings: StageModelSettings {
        StageModelSettings(
            speech: currentSpeech,
            refinement: currentProvider == .appleIntelligence ? .appleIntelligence : .azureFoundry,
            realtimeDeployment: currentRealtimeDeployment,
            realtimeStreamModel: currentStreamModel,
            gptRealtimeDeployment: currentGPTRealtimeDeployment,
            maiRealtimeDeployment: currentMAIRealtimeDeployment
        )
    }

    private let batchConfigured: Bool
    private let realtimeConfigured: Bool
    private let realtimeCredentialsConfigured: Bool
    private let defaultRealtimeDeployment: String
    private let defaultGPTRealtimeDeployment: String
    private let defaultMAIRealtimeDeployment: String
    private let azureTextConfigured: Bool
    private let preferences: any PreferencesStore
    private let notificationCenter: NotificationCenter
    private let logger: any VoxLogger
    private let onPresetChange: (@MainActor @Sendable (Preset) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var pendingUpdate: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0

    public init(
        batchConfigured: Bool,
        realtimeConfigured: Bool = false,
        realtimeCredentialsConfigured: Bool = false,
        defaultRealtimeDeployment: String = "",
        defaultGPTRealtimeDeployment: String = "",
        defaultMAIRealtimeDeployment: String = "",
        azureTextConfigured: Bool,
        preferences: any PreferencesStore,
        notificationCenter: NotificationCenter = .default,
        logger: any VoxLogger = NoopVoxLogger(),
        onPresetChange: (@MainActor @Sendable (Preset) -> Void)? = nil
    ) {
        self.batchConfigured = batchConfigured
        self.realtimeConfigured = realtimeConfigured
        self.realtimeCredentialsConfigured = realtimeCredentialsConfigured
        self.defaultRealtimeDeployment = defaultRealtimeDeployment
        self.defaultGPTRealtimeDeployment = defaultGPTRealtimeDeployment
        self.defaultMAIRealtimeDeployment = defaultMAIRealtimeDeployment
        self.azureTextConfigured = azureTextConfigured
        self.preferences = preferences
        self.notificationCenter = notificationCenter
        self.logger = logger
        self.onPresetChange = onPresetChange
        currentProvider = .azureFoundry
        currentSpeech = .batch
        preset = IOSPresetMapping.preset(
            batchConfigured: batchConfigured,
            realtimeConfigured: realtimeConfigured || (realtimeCredentialsConfigured && !defaultRealtimeDeployment.isEmpty),
            azureTextConfigured: azureTextConfigured,
            speech: currentSpeech,
            provider: currentProvider,
            skipContentAnalysis: true
        )
        for name in [PreferencesNotification.llmProviderDidChange,
                     PreferencesNotification.llmAnalysisSettingsDidChange,
                     PreferencesNotification.stageModelsDidChange] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleApplyPreferences() }
            })
        }
        scheduleApplyPreferences()
    }

    public func waitForPendingChanges() async {
        await pendingUpdate?.value
    }

    public func refresh() {
        scheduleApplyPreferences()
    }

    private func scheduleApplyPreferences() {
        pendingUpdate?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let preferences = self.preferences
        pendingUpdate = Task { [weak self] in
            let storedProvider: String? = await preferences.getValue(for: .llmProvider)
            let storedSpeech: String? = await preferences.getValue(for: .speechModel)
            let stages = await StageModelSettings.load(from: preferences)
            _ = await preferences.getValue(for: .llmSkipContentAnalysis, default: true)
            guard let self else { return }
            await MainActor.run {
                guard !Task.isCancelled, self.refreshGeneration == generation else { return }
                if let storedProvider, let provider = LLMProviderType(rawValue: storedProvider) {
                    self.currentProvider = provider
                }
                if let storedSpeech, let speech = SpeechModelSelection(rawValue: storedSpeech) {
                    self.currentSpeech = speech
                }
                let effectiveDeployment = stages.resolvedRealtimeDeployment(
                    gptDefault: self.defaultGPTRealtimeDeployment,
                    maiDefault: self.defaultMAIRealtimeDeployment,
                    legacyDefault: self.defaultRealtimeDeployment
                )
                let effectiveRealtimeConfigured = self.realtimeConfigured || (self.realtimeCredentialsConfigured && !effectiveDeployment.isEmpty)
                self.currentRealtimeDeployment = effectiveDeployment
                self.currentStreamModel = stages.realtimeStreamModel
                self.currentGPTRealtimeDeployment = stages.gptRealtimeDeployment
                self.currentMAIRealtimeDeployment = stages.maiRealtimeDeployment
                self.preset = IOSPresetMapping.preset(
                    batchConfigured: self.batchConfigured,
                    realtimeConfigured: effectiveRealtimeConfigured,
                    azureTextConfigured: self.azureTextConfigured,
                    speech: self.currentSpeech,
                    provider: self.currentProvider,
                    skipContentAnalysis: true
                )
                self.onPresetChange?(self.preset)
                if !self.batchConfigured {
                    self.logger.log(.warning, "Azure transcription configuration missing; actual_provider=appleSpeech", fields: [])
                }
            }
        }
    }

    isolated deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
        pendingUpdate?.cancel()
    }
}

public final class WorkflowTranscriptionCoordinator: TranscriptionCoordinator, ModelLoadingObservable,
    ModelLoadingStartControlling, MultiRecognizerTranscriber, QuickRecordingReleaseControlling, @unchecked Sendable { // Sendable: App-side Combine bridge wrapper around CombineTranscriptionCoordinator; all mutable state is synchronized by the wrapped coordinator.
    public let presetID: String
    public let preset: Preset
    public let core: any SpeechSessionSource
    private let coordinator: CombineTranscriptionCoordinator
    private let loading: CombineModelLoadingObservable?

    public init(source: any SpeechSessionSource, preset: Preset) {
        self.core = source
        self.preset = preset
        presetID = preset.id
        coordinator = CombineTranscriptionCoordinator.wrap(source)
        if let source = source as? any ModelLoadingStateProviding {
            loading = CombineModelLoadingObservable(source: source)
        } else {
            loading = nil
        }
    }

    public static func wrap(_ source: any SpeechSessionSource, preset: Preset) -> WorkflowTranscriptionCoordinator {
        WorkflowTranscriptionCoordinator(source: source, preset: preset)
    }

    public var audioCaptureService: any AudioCaptureService { coordinator.audioCaptureService }
    public var speechRecognitionService: any SpeechRecognitionService { coordinator.speechRecognitionService }
    public var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { coordinator.finalResultPublisher }
    public var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> { coordinator.liveResultPublisher }
    public var audioLevelPublisher: AnyPublisher<Float, Never> { coordinator.audioLevelPublisher }
    public var isTranscribing: Bool { coordinator.isTranscribing }
    public func start(language: Locale) async throws { try await coordinator.start(language: language) }
    public func stop() async { await coordinator.stop() }
    public func pause() { coordinator.pause() }
    public func resume() { coordinator.resume() }
    public func prepareQuickRecording() throws { try coordinator.prepareQuickRecording() }
    public func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        try coordinator.freezeQuickRecordingRelease()
    }
    public func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        try await coordinator.completeQuickRecordingRelease(snapshot)
    }
    public var merger: (any TranscriptionMerger)? { (core as? any MultiRecognizerSpeechSource)?.merger }
    public var modelLoadingState: ModelLoadingState { loading?.modelLoadingState ?? .idle }
    public var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> {
        loading?.modelLoadingStatePublisher ?? Just(.idle).eraseToAnyPublisher()
    }
    public var blocksRecordingUntilModelReady: Bool {
        (core as? any ModelLoadingStartControlling)?.blocksRecordingUntilModelReady ?? false
    }
}

public enum RefineWorkflowConfigurationError: Error, LocalizedError, Sendable, Equatable {
    case unavailable
    public var errorDescription: String? { "所选文本模型尚未配置，请检查语音与文本设置。" }
}

public protocol RefineWorkflowRunning: AnyObject, Sendable {
    var isConfigured: Bool { get }
    var activePreset: Preset { get }
    var currentProviderType: LLMProviderType? { get }
    var resolvedAnalysisRouting: [AnalysisStep: LLMProviderType] { get }
    var isContentAnalysisSkipped: Bool { get }
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error>
    func cancel()
}

public final class RefineWorkflowRunner: RefineWorkflowRunning, Sendable {
    private struct Snapshot: Sendable {
        let preset: Preset
        let runtime: WorkflowRuntime
        let configured: Bool
        let provider: LLMProviderType?
        let routing: [AnalysisStep: LLMProviderType]
        let skip: Bool
    }

    private let state: Mutex<Snapshot>

    public init(
        preset: Preset = .default,
        configuration: WorkflowExecutionConfiguration = WorkflowExecutionConfiguration(),
        azureTextConfigured: Bool = true
    ) {
        state = Mutex(Self.snapshot(preset: preset, configuration: configuration, azureTextConfigured: azureTextConfigured))
    }

    public var isConfigured: Bool { state.withLock { $0.configured } }
    public var activePreset: Preset { state.withLock { $0.preset } }
    public var currentProviderType: LLMProviderType? { state.withLock { $0.provider } }
    public var resolvedAnalysisRouting: [AnalysisStep: LLMProviderType] { state.withLock { $0.routing } }
    public var isContentAnalysisSkipped: Bool { state.withLock { $0.skip } }

    public func configure(
        preset: Preset,
        configuration: WorkflowExecutionConfiguration,
        azureTextConfigured: Bool
    ) {
        state.withLock { $0 = Self.snapshot(preset: preset, configuration: configuration, azureTextConfigured: azureTextConfigured) }
    }

    public func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        let snapshot = state.withLock { $0 }
        guard snapshot.configured else { throw RefineWorkflowConfigurationError.unavailable }
        return try await snapshot.runtime.refine(request, preset: snapshot.preset)
    }

    public func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        let snapshot = state.withLock { $0 }
        guard snapshot.configured else { throw RefineWorkflowConfigurationError.unavailable }
        return try await snapshot.runtime.refineStreaming(request, preset: snapshot.preset)
    }

    public func cancel() { state.withLock { $0.runtime.cancel() } }

    private static func snapshot(
        preset: Preset,
        configuration: WorkflowExecutionConfiguration,
        azureTextConfigured: Bool
    ) -> Snapshot {
        let provider: LLMProviderType? = preset.refine.nodes.first { node in
            node.kind == NodeKindID.llmApple || node.kind == NodeKindID.llmAzure
        }
            .flatMap { node in
                node.kind == NodeKindID.llmAzure ? LLMProviderType.azureFoundry : LLMProviderType.appleIntelligence
            }
        let routing: [AnalysisStep: LLMProviderType] = Dictionary(uniqueKeysWithValues: AnalysisStep.allCases.compactMap { step in
            guard let node = preset.refine.nodes.first(where: { $0.kind.rawValue.hasSuffix(".\(step.rawValue)") }) else { return nil }
            guard case .string(let value)? = node.params["analysis.\(step.rawValue).provider"],
                  let provider = LLMProviderType(rawValue: value) else { return nil }
            return (step, provider)
        })
        let skip = preset.refine.nodes.contains { $0.params["analysis.skip"] == .string("true") }
        let configured = provider != LLMProviderType.azureFoundry || azureTextConfigured
        return Snapshot(preset: preset, runtime: WorkflowRuntime(configuration: configuration), configured: configured,
                        provider: provider, routing: routing, skip: skip)
    }
}
