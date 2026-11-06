import Foundation
import VoxCore
import VoxLLM
import VoxRefine
import VoxSpeech

public struct WorkflowExecutionConfiguration: Sendable {
    public let azureFoundryConfig: LLMProviderConfig?
    public let whisperConfig: AzureWhisperConfig?
    public let realtimeConfig: AzureRealtimeTranscriptionConfig?
    public let logger: any VoxLogger
    public let telemetry: any VoxTelemetry
    public let storageLocations: VoxStorageLocations?
    package let providers: [LLMProviderType: any LLMProvider]
    package let merger: (any TranscriptionMerger)?
    package let speechFactories: [NodeKindID: any SpeechSessionFactory]

    public init(azureFoundryConfig: LLMProviderConfig? = nil, whisperConfig: AzureWhisperConfig? = nil,
                realtimeConfig: AzureRealtimeTranscriptionConfig? = nil,
                logger: any VoxLogger = NoopVoxLogger(), telemetry: any VoxTelemetry = NoopVoxTelemetry(),
                storageLocations: VoxStorageLocations? = nil) {
        self.azureFoundryConfig = azureFoundryConfig
        self.whisperConfig = whisperConfig
        self.realtimeConfig = realtimeConfig
        self.logger = logger
        self.telemetry = telemetry
        self.storageLocations = storageLocations
        var providers: [LLMProviderType: any LLMProvider] = [.appleIntelligence: AppleIntelligenceProvider(logger: logger)]
        if let azureFoundryConfig { providers[.azureFoundry] = AzureFoundryProvider(config: azureFoundryConfig, logger: logger) }
        self.providers = providers
        self.merger = Self.makeMerger(providers: providers, logger: logger)
        speechFactories = [:]
    }

    package init(providers: [LLMProviderType: any LLMProvider], merger: (any TranscriptionMerger)? = nil,
                 speechFactories: [NodeKindID: any SpeechSessionFactory] = [:],
                 logger: any VoxLogger = NoopVoxLogger(), telemetry: any VoxTelemetry = NoopVoxTelemetry()) {
        azureFoundryConfig = nil
        whisperConfig = nil
        realtimeConfig = nil
        storageLocations = nil
        self.providers = providers
        self.merger = merger ?? Self.makeMerger(providers: providers, logger: logger)
        self.speechFactories = speechFactories
        self.logger = logger
        self.telemetry = telemetry
    }

    private static func makeMerger(providers: [LLMProviderType: any LLMProvider], logger: any VoxLogger) -> any TranscriptionMerger {
        let service = DefaultLLMService(providers: providers, logger: logger)
        let provider: LLMProviderType = providers[.azureFoundry] == nil ? .appleIntelligence : .azureFoundry
        try? service.setProvider(LLMProviderConfig(providerType: provider, modelIdentifier: "workflow"))
        return LLMTranscriptionMerger(llmService: service, logger: logger)
    }

    package func speechSource(for kind: NodeKindID) async throws -> any SpeechSessionSource {
        if let factory = speechFactories[kind] { return try await factory.makeSource() }
        guard let storageLocations else { throw WorkflowRuntimeError.nodeFailed }
        switch kind {
        case .speechApple: return AppleSpeechTranscriber(logger: logger, storageLocations: storageLocations)
        case .speechAzureBatch:
            guard let whisperConfig else { throw WorkflowRuntimeError.nodeFailed }
            return AzureWhisperTranscriber(config: whisperConfig, logger: logger, storageLocations: storageLocations)
        case .speechAzureRealtime:
            guard let whisperConfig, let realtimeConfig else { throw WorkflowRuntimeError.nodeFailed }
            return HybridWhisperTranscriber(whisperConfig: whisperConfig, realtimeConfig: realtimeConfig,
                                           logger: logger, storageLocations: storageLocations)
        default: throw WorkflowRuntimeError.nodeFailed
        }
    }
}
