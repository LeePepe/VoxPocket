import Foundation
import LLMKit
import TranscriptionKit

/// 转录器提供者选择
enum TranscriberProvider {
    /// WhisperKit 本地模型（Core ML）
    case localWhisperKit
    /// Apple Speech Framework（默认，无需 API Key）
    case appleSpeech
    /// Azure OpenAI Whisper 纯批量模式（录音结束后送 Whisper，无实时结果）
    case azureWhisper
    /// 混合模式：Apple Speech 提供实时结果 + 自动停止，有内容时再用 Whisper 提升最终质量
    case hybridWhisper
    /// 混合模式（本地）：Apple Speech 提供实时结果 + 自动停止，有内容时再用本地 WhisperKit 提升最终质量
    case hybridLocalWhisper
}

/// App 内 LLM 固定配置（非敏感项）
enum LLMAppConfig {

    // MARK: - Transcriber

    /// 默认转录器提供者
    ///
    /// 设为 `.azureWhisper` 时，需在 Scheme 环境变量中配置 `whisperkey`。
    /// 未配置 API Key 时自动回退到 `.appleSpeech`。
    static let defaultTranscriberProvider: TranscriberProvider = .hybridWhisper
    /// 默认 provider（当用户未在设置中显式选择时）
    static let defaultProvider: LLMProviderType = .appleIntelligence

    /// Azure Foundry 配置
    ///
    /// `azureEndpoint`：从环境变量 `AZURE_FOUNDRY_ENDPOINT` 读取；
    /// 未配置时使用空占位，Azure 功能将不可用。
    /// `azureModelIdentifier`：可通过 `AZURE_FOUNDRY_MODEL` 覆盖。
    static let azureEndpoint: URL = {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["AZURE_FOUNDRY_ENDPOINT"], let url = URL(string: raw) { return url }
        return URL(string: "https://your-resource.services.ai.azure.com")!
    }()
    static let azureModelIdentifier: String = {
        ProcessInfo.processInfo.environment["AZURE_FOUNDRY_MODEL"] ?? "gpt-4o"
    }()
    static let azureAPIVersion = "2024-05-01-preview"
    static let azureAuthMode: AzureFoundryAuthMode = .bearer
    
    /// 分析步骤 provider 覆盖（当前默认不覆盖，跟随当前 provider）
    static let analysisProviderOverrides: [AnalysisStep: LLMProviderType] = [.intent: .appleIntelligence, .tone: .appleIntelligence]

    static func analysisOptions() -> [String: String] {
        var options: [String: String] = [:]
        for (step, provider) in analysisProviderOverrides {
            options["analysis.\(step.rawValue).provider"] = provider.rawValue
        }
        return options
    }
}
