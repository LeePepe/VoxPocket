import Foundation
import VoxCore
import VoxSpeech
import VoxSpeechWhisperKit
import VoxWorkflow

public extension Preset {
    static let localWhisperKit = Preset(
        id: "local.whisperkit",
        speech: WorkflowDefinition(entry: .speech) {
            NodeSpec(id: "capture", kind: .captureMicrophone)
            NodeSpec(id: "local", kind: .speechWhisperKitLocal, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "local", port: "text")])
        },
        refine: Preset.appleSpeech.refine
    )

    static let hybridLocal = Preset(
        id: "hybrid.local",
        speech: WorkflowDefinition(entry: .speech) {
            NodeSpec(id: "capture", kind: .captureMicrophone)
            NodeSpec(id: "local", kind: .speechWhisperKitLocal, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "apple", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "merge", kind: .mergeLLM,
                     inputs: [PortRef(nodeID: "apple", port: "text"), PortRef(nodeID: "local", port: "text")])
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "merge", port: "text")])
        },
        refine: Preset.appleSpeech.refine
    )
}

public final class WorkflowWhisperKitSpeechSource: SpeechSessionSource, MultiRecognizerSpeechSource,
    ModelLoadingStateProviding, ModelLoadingStartControlling, Sendable {
    private let source: any SpeechSessionSource
    private let loadingSource: (any ModelLoadingStateProviding)?
    private let startController: (any ModelLoadingStartControlling)?
    public let preset: Preset

    public init(source: any SpeechSessionSource, preset: Preset = .localWhisperKit) {
        self.source = source
        self.loadingSource = source as? any ModelLoadingStateProviding
        self.startController = source as? any ModelLoadingStartControlling
        self.preset = preset
    }

    public init(primary: any SpeechSessionSource, fallback: any SpeechSessionSource, preset: Preset = .localWhisperKit) {
        let coordinator = LoadingFallbackTranscriptionCoordinator(primary: primary, fallback: fallback)
        self.source = coordinator
        self.loadingSource = coordinator.primaryModelLoadingSource
        self.startController = primary as? any ModelLoadingStartControlling
        self.preset = preset
    }

    public convenience init(hybrid source: HybridLocalWhisperTranscriber, preset: Preset = .hybridLocal) {
        self.init(source: source, preset: preset)
    }

    public var merger: (any TranscriptionMerger)? { (source as? any MultiRecognizerSpeechSource)?.merger }
    public var supportedLanguages: [Locale] { source.supportedLanguages }
    public var providerKind: ASRProviderType { source.providerKind }
    public var isActive: Bool { source.isActive }
    public func requestMicrophonePermission() async -> Bool { await source.requestMicrophonePermission() }
    public func requestSpeechPermission() async -> Bool { await source.requestSpeechPermission() }
    public var hasMicrophonePermission: Bool { source.hasMicrophonePermission }
    public var hasSpeechPermission: Bool { source.hasSpeechPermission }
    public func captureStates() -> AsyncStream<AudioCaptureState> { source.captureStates() }
    public func audioLevels() -> AsyncStream<Float> { source.audioLevels() }
    public func startSession(language: Locale) async throws -> any SpeechSession { try await source.startSession(language: language) }
    public var modelLoadingState: ModelLoadingState { loadingSource?.modelLoadingState ?? .idle }
    public func modelLoadingStates() -> AsyncStream<ModelLoadingState> {
        loadingSource?.modelLoadingStates() ?? AsyncStream { $0.yield(.idle); $0.finish() }
    }
    public var blocksRecordingUntilModelReady: Bool { startController?.blocksRecordingUntilModelReady ?? false }
    public func startModelPreloadIfNeeded() {
        (source as? any ModelPreloadControlling)?.startModelPreloadIfNeeded()
    }
}

public enum WorkflowWhisperKit {
    @discardableResult
    public static func registerNodes(in registry: NodeRegistry) -> VoxLabel {
        registry.register(
            NodeSignature(kind: .speechWhisperKitLocal, allowedEntries: [.speech], inputTypes: [.audio], outputType: .text),
            handler: WhisperKitWorkflowNodeHandler())
    }
}

private struct WhisperKitWorkflowNodeHandler: WorkflowNodeHandler {
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        if context.configuration.speechFactories[.speechWhisperKitLocal] != nil {
            return try await BuiltInWorkflowNodeHandler.transcribe(context: context)
        }
        if case .speechSession = context.inputs.first {
            return try await BuiltInWorkflowNodeHandler.transcribe(context: context)
        }
        if case .audio(let capture) = context.inputs.first, capture.suppliedSession != nil {
            return try await BuiltInWorkflowNodeHandler.transcribe(context: context)
        }
        guard let storageLocations = context.configuration.storageLocations else { throw WorkflowRuntimeError.nodeFailed }
        let source = WhisperKitTranscriber(config: LocalWhisperKitConfig(), logger: context.configuration.logger,
            telemetry: context.configuration.telemetry, storageLocations: storageLocations)
        guard await source.requestMicrophonePermission() else { throw WorkflowRuntimeError.nodeFailed }
        let session = try await source.startSession(language: Locale(identifier: "zh-Hans"))
        return try await BuiltInWorkflowNodeHandler.consume(session: session, context: context)
    }
}
