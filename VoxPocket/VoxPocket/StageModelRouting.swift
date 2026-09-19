import Foundation
import Preferences
import TranscriptionKit
import LLMKit

/// App 组合根将非敏感偏好映射到已有适配器；每次录音捕获一次选择。
@MainActor
enum StageModelRouting {
    static func makeTranscriber(
        environment: [String: String], preferences: any PreferencesStore,
        beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)? = nil
    ) -> any TranscriptionCoordinator {
        DefaultSelectableTranscriptionCoordinator(permissionCoordinator: AppleSpeechTranscriber()) {
            let settings = await StageModelSettings.load(from: preferences)
            return try await MainActor.run {
                try Task.checkCancellation()
                return prepareSession(settings: settings, environment: environment, beforeSession: beforeSession)
            }
        }
    }

    static func prepareSession(settings: StageModelSettings, environment: [String: String],
                               beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)?) -> any TranscriptionCoordinator {
        beforeSession?(settings)
        return resolveTranscriber(settings: settings, environment: environment)
    }

    static func resolveTranscriber(settings: StageModelSettings, environment: [String: String]) -> any TranscriptionCoordinator {
        let selected = resolvedSpeechModel(settings: settings, environment: environment)
        guard selected != .appleSpeech,
              let batch = LLMAppConfig.transcriptionConfig(environment: environment) else { return AppleSpeechTranscriber() }
        let realtime = selected == .realtime
            ? LLMAppConfig.realtimeTranscriptionConfig(environment: environment, deploymentOverride: settings.realtimeDeployment)
            : nil
        return HybridWhisperTranscriber(whisperConfig: batch, realtimeConfig: realtime)
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

    nonisolated static func analysisOptions(settings: StageModelSettings) -> [String: String] {
        ["analysis.intent.provider": settings.intent.rawValue,
         "analysis.entities.provider": settings.intent.rawValue,
         "analysis.tags.provider": settings.intent.rawValue,
         "analysis.params.provider": settings.intent.rawValue,
         "analysis.tone.provider": settings.tone.rawValue]
    }

    nonisolated static func applyTextModels(_ settings: StageModelSettings, to service: DefaultLLMService) throws {
        let provider: LLMProviderType = settings.refinement == .azureFoundry ? .azureFoundry : .appleIntelligence
        // 模型对象和凭据由启动配置创建；这里仅切换已注册模型，不把凭据写入偏好。
        try service.setProvider(.init(providerType: provider, modelIdentifier: "configured",
                                     options: analysisOptions(settings: settings)))
        service.setSkipContentAnalysis(settings.skipAnalysis)
    }

    static func availability(environment: [String: String]) -> ModelSettingsAvailability {
        let hasRealtimeCredentials = LLMAppConfig.realtimeTranscriptionConfig(environment: environment,
                                                                             deploymentOverride: "validation") != nil
        let textKey = LLMAppConfig.refinementAPIKey(environment: environment)
        let textEndpoint = environment["AZURE_FOUNDRY_ENDPOINT"] ?? environment["AZURE_OPENAI_ENDPOINT"] ?? ""
        let textURL = URL(string: textEndpoint)
        let textConfigured = textKey != nil && textURL?.scheme == "https" && textURL?.host != nil
            && textURL?.user == nil && textURL?.password == nil
        return ModelSettingsAvailability(
            batchConfigured: LLMAppConfig.transcriptionConfig(environment: environment) != nil,
            realtimeCredentialsConfigured: hasRealtimeCredentials,
            realtimeDeployment: environment["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] ?? "",
            textConfigured: textConfigured,
            textModelName: textConfigured ? environment["AZURE_FOUNDRY_MODEL"] ?? "默认文本模型" : ""
        )
    }
}
