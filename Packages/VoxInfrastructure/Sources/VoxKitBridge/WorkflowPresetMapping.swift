import Foundation
import Combine
import Synchronization
import VoxCore
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
        let overridden = Preset.default.overriding([
            "speech": speech,
            "analysis.intent": settings.intent.rawValue,
            "analysis.entities": settings.intent.rawValue,
            "analysis.tags": settings.intent.rawValue,
            "analysis.params": settings.intent.rawValue,
            "analysis.tone": settings.tone.rawValue,
            "analysis.skip": settings.skipAnalysis ? "true" : "false",
            "refine.provider": settings.refinement.rawValue
        ])
        return Preset(id: overridden.id, speech: Self.speechDefinition(for: speech), refine: overridden.refine)
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

    private static func speechDefinition(for choice: String) -> WorkflowDefinition {
        switch choice {
        case "appleSpeech": return Preset.appleSpeech.speech
        case "batch":
            return WorkflowDefinition(entry: .speech) {
                NodeSpec(id: "capture", kind: .captureMicrophone)
                NodeSpec(id: "apple", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
                NodeSpec(id: "batch", kind: .speechAzureBatch, inputs: [PortRef(nodeID: "capture", port: "audio")])
                NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "batch", port: "text")])
            }
        case "realtime":
            return WorkflowDefinition(entry: .speech) {
                NodeSpec(id: "capture", kind: .captureMicrophone)
                NodeSpec(id: "apple", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
                NodeSpec(id: "realtime", kind: .speechAzureRealtime, inputs: [PortRef(nodeID: "capture", port: "audio")])
                NodeSpec(id: "batch", kind: .speechAzureBatch, inputs: [PortRef(nodeID: "capture", port: "audio")])
                NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "batch", port: "text")])
            }
        default: return Preset.default.speech
        }
    }
}

public struct IOSPresetMapping: Sendable {
    public let batchConfigured: Bool
    public let azureTextConfigured: Bool
    public let provider: LLMProviderType
    public let skipContentAnalysis: Bool

    public init(
        batchConfigured: Bool,
        azureTextConfigured: Bool,
        provider: LLMProviderType = .azureFoundry,
        skipContentAnalysis: Bool = false
    ) {
        self.batchConfigured = batchConfigured
        self.azureTextConfigured = azureTextConfigured
        self.provider = provider
        self.skipContentAnalysis = skipContentAnalysis
    }

    public var preset: Preset {
        Self.preset(batchConfigured: batchConfigured, azureTextConfigured: azureTextConfigured,
                    provider: provider, skipContentAnalysis: skipContentAnalysis)
    }

    public static func preset(
        batchConfigured: Bool,
        azureTextConfigured: Bool,
        provider: LLMProviderType = .azureFoundry,
        skipContentAnalysis: Bool = false
    ) -> Preset {
        let base = batchConfigured ? Preset.hybridAzure : Preset.appleSpeech
        let overridden = base.overriding([
            "speech": batchConfigured ? "batch" : "appleSpeech",
            "analysis.intent": LLMProviderType.appleIntelligence.rawValue,
            "analysis.entities": provider.rawValue,
            "analysis.tags": provider.rawValue,
            "analysis.params": provider.rawValue,
            "analysis.tone": LLMProviderType.appleIntelligence.rawValue,
            "analysis.skip": skipContentAnalysis ? "true" : "false",
            "refine.provider": provider.rawValue
        ])
        let speech: WorkflowDefinition
        if batchConfigured {
            speech = StagePresetMapping.preset(settings: .init(speech: .batch),
                batchConfigured: true, realtimeConfigured: false, azureTextConfigured: azureTextConfigured).speech
        } else {
            speech = Preset.appleSpeech.speech
        }
        return Preset(id: overridden.id, speech: speech, refine: overridden.refine)
    }

    public static func makePreset(
        batchConfigured: Bool,
        azureTextConfigured: Bool,
        provider: LLMProviderType = .azureFoundry,
        skipContentAnalysis: Bool = false
    ) -> Preset {
        preset(batchConfigured: batchConfigured, azureTextConfigured: azureTextConfigured,
               provider: provider, skipContentAnalysis: skipContentAnalysis)
    }

    public func exportedPipeline() -> WorkflowPipelineSnapshot {
        preset.exportedPipeline(batchConfigured: batchConfigured, realtimeConfigured: false,
                                azureTextConfigured: azureTextConfigured)
    }

}

@MainActor
public final class IOSPresetPreferenceBinding: @unchecked Sendable {
    public private(set) var currentProvider: LLMProviderType
    public private(set) var preset: Preset
    public var activePreset: Preset { preset }

    private let batchConfigured: Bool
    private let azureTextConfigured: Bool
    private let preferences: any PreferencesStore
    private let notificationCenter: NotificationCenter
    private let logger: any VoxLogger
    private var observers: [NSObjectProtocol] = []
    private var pendingUpdate: Task<Void, Never>?

    public init(
        batchConfigured: Bool,
        azureTextConfigured: Bool,
        preferences: any PreferencesStore,
        notificationCenter: NotificationCenter = .default,
        logger: any VoxLogger = NoopVoxLogger()
    ) {
        self.batchConfigured = batchConfigured
        self.azureTextConfigured = azureTextConfigured
        self.preferences = preferences
        self.notificationCenter = notificationCenter
        self.logger = logger
        currentProvider = .azureFoundry
        preset = IOSPresetMapping.preset(batchConfigured: batchConfigured, azureTextConfigured: azureTextConfigured)
        for name in [PreferencesNotification.llmProviderDidChange,
                     PreferencesNotification.llmAnalysisSettingsDidChange] {
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
        let preferences = self.preferences
        pendingUpdate = Task { [weak self] in
            let storedProvider: String? = await preferences.getValue(for: .llmProvider)
            let skip: Bool = await preferences.getValue(for: .llmSkipContentAnalysis, default: false)
            guard let self else { return }
            await MainActor.run {
                if let storedProvider, let provider = LLMProviderType(rawValue: storedProvider) {
                    self.currentProvider = provider
                }
                self.preset = IOSPresetMapping.preset(
                    batchConfigured: self.batchConfigured,
                    azureTextConfigured: self.azureTextConfigured,
                    provider: self.currentProvider,
                    skipContentAnalysis: skip
                )
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
    ModelLoadingStartControlling, MultiRecognizerTranscriber, @unchecked Sendable {
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
