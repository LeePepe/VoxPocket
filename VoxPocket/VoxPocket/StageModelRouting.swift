import Foundation
import VoxCore
import VoxKitBridge
import VoxWorkflow
import Preferences
import VoxSpeech

/// App 组合根将非敏感偏好映射到已有适配器；每次录音捕获一次选择。
@MainActor
enum StageModelRouting {
    static func makeTranscriber(
        environment: [String: String], preferences: any PreferencesStore, sdk: SDKHostConfiguration,
        beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)? = nil
    ) -> any SpeechSessionSource {
        DefaultSelectableTranscriptionCoordinator(
            permissionCoordinator: AppleSpeechTranscriber(logger: sdk.logger, storageLocations: sdk.storageLocations),
            factory: StageSpeechSessionFactory(environment: environment, preferences: preferences,
                sdk: sdk, beforeSession: beforeSession))
    }

    static func prepareSession(settings: StageModelSettings, environment: [String: String],
                               beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)?, sdk: SDKHostConfiguration? = nil) -> any SpeechSessionSource {
        let sdk = sdk ?? defaultSDK(environment: environment)
        beforeSession?(settings)
        let availability = availability(environment: environment)
        let realtimeConfigured = LLMAppConfig.realtimeTranscriptionConfig(
            environment: environment, deploymentOverride: settings.realtimeDeployment) != nil
        let preset = StagePresetMapping.preset(settings: settings,
            batchConfigured: availability.batchConfigured,
            realtimeConfigured: realtimeConfigured,
            azureTextConfigured: availability.textConfigured)
        guard preset.speech.nodes.contains(where: { $0.kind == .speechAzureBatch }),
              let batch = LLMAppConfig.transcriptionConfig(environment: environment) else {
            return AppleSpeechTranscriber(logger: sdk.logger, storageLocations: sdk.storageLocations)
        }
        let realtime = preset.speech.nodes.contains(where: { $0.kind == .speechAzureRealtime })
            ? LLMAppConfig.realtimeTranscriptionConfig(environment: environment, deploymentOverride: settings.realtimeDeployment)
            : nil
        return HybridWhisperTranscriber(whisperConfig: batch, realtimeConfig: realtime,
            logger: sdk.logger, storageLocations: sdk.storageLocations)
    }

    private static func defaultSDK(environment: [String: String]) -> SDKHostConfiguration {
        SDKHostConfiguration(storageLocations: SDKHostConfiguration.storageLocations(),
            logger: NoopVoxLogger(), telemetry: NoopVoxTelemetry(),
            credentials: SDKHostConfiguration.credentials(environment: environment))
    }

    static func resolvedSpeechModel(settings: StageModelSettings, environment: [String: String]) -> SpeechModelSelection {
        guard settings.speech != .appleSpeech,
              LLMAppConfig.transcriptionConfig(environment: environment) != nil else { return .appleSpeech }
        if settings.speech == .realtime,
           LLMAppConfig.realtimeTranscriptionConfig(environment: environment, deploymentOverride: settings.realtimeDeployment) != nil {
            return .realtime
        }
        return .batch
    }

    static func availability(environment: [String: String]) -> ModelSettingsAvailability {
        let hasRealtimeCredentials = LLMAppConfig.realtimeTranscriptionConfig(environment: environment,
                                                                             deploymentOverride: "validation") != nil
        let textKey = LLMAppConfig.refinementAPIKey(environment: environment)
        let textConfigured = textKey != nil && LLMAppConfig.azureEndpoint(environment: environment) != nil
        return ModelSettingsAvailability(
            batchConfigured: LLMAppConfig.transcriptionConfig(environment: environment) != nil,
            realtimeCredentialsConfigured: hasRealtimeCredentials,
            realtimeDeployment: environment["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] ?? "",
            textConfigured: textConfigured,
            textModelName: textConfigured ? environment["AZURE_FOUNDRY_MODEL"] ?? "默认文本模型" : ""
        )
    }
}

internal final class StageSpeechSessionFactory: SpeechSessionFactory, @unchecked Sendable {
    let environment: [String: String]
    let preferences: any PreferencesStore
    let sdk: SDKHostConfiguration
    let beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)?
    @MainActor private var cachedSettings: StageModelSettings?
    @MainActor private var cachedSource: (any SpeechSessionSource)?

    @MainActor
    init(
        environment: [String: String],
        preferences: any PreferencesStore,
        sdk: SDKHostConfiguration,
        beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)?
    ) {
        self.environment = environment
        self.preferences = preferences
        self.sdk = sdk
        self.beforeSession = beforeSession
        let initial = LLMAppConfig.initialStageModelSettings
        self.cachedSettings = initial
        self.cachedSource = StageModelRouting.prepareSession(
            settings: initial, environment: environment,
            beforeSession: nil, sdk: sdk
        )
    }

    func makeSource() async throws -> any SpeechSessionSource {
        let settings = await StageModelSettings.load(from: preferences)
        return try await MainActor.run {
            try Task.checkCancellation()
            if cachedSettings == settings, let cachedSource {
                beforeSession?(settings)
                return cachedSource
            }
            let created = StageModelRouting.prepareSession(
                settings: settings, environment: environment,
                beforeSession: beforeSession, sdk: sdk
            )
            cachedSettings = settings
            cachedSource = created
            return created
        }
    }
}
