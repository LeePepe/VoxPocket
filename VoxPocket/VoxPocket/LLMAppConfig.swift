import Foundation
import LLMKit

/// App 内 LLM 固定配置（非敏感项）
enum LLMAppConfig {
    /// 默认 provider（当用户未在设置中显式选择时）
    static let defaultProvider: LLMProviderType = .appleIntelligence

    /// Azure Foundry 固定配置
    static let azureEndpoint = URL(string: "https://usllm.services.ai.azure.com")!
    static let azureModelIdentifier = "Kimi-K2.5"
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
