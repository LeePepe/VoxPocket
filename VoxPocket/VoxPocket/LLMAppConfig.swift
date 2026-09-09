import Foundation
import LLMKit
import TranscriptionKit
import Preferences
import OSLog

/// 转录器提供者选择
enum TranscriberProvider {
    /// WhisperKit 本地模型（Core ML）
    case localWhisperKit
    /// Apple Speech Framework（本地回退，无需 API Key）
    case appleSpeech
    /// Azure OpenAI Whisper 纯批量模式（录音结束后送 Whisper，无实时结果）
    case azureWhisper
    /// 混合模式：Apple Speech 提供实时结果 + 自动停止，有内容时再用 Whisper 提升最终质量
    case hybridWhisper
    /// 混合模式（本地）：Apple Speech 提供实时结果 + 自动停止，有内容时再用本地 WhisperKit 提升最终质量
    case hybridLocalWhisper
}

/// App 内 LLM 固定配置（非敏感项）
@MainActor
enum LLMAppConfig {
    private(set) static var runtimeEnvironment = ProcessInfo.processInfo.environment
    private static let configurationTask = Task {
        try await DefaultPrivateModelConfigurationLoader().load(environment: ProcessInfo.processInfo.environment)
    }

    /// SwiftUI 及各入口创建服务之前等待同一次后台加载；不修改进程全局环境。
    static func loadRuntimeConfiguration() async throws {
        let configuration = try await configurationTask.value
        runtimeEnvironment = configuration.environmentValues
        let source = configuration.loadedPrivateFile ? "private_file" : "environment"
        let speechReady = transcriptionConfig(environment: runtimeEnvironment) != nil
        let textReady = refinementAPIKey(environment: runtimeEnvironment) != nil && azureEndpoint != nil
        Logger(subsystem: "com.leepepe.voxpocket", category: "ModelConfiguration")
            .info("source=\(source, privacy: .public) transcription_ready=\(speechReady) refinement_ready=\(textReady)")
    }

    // MARK: - Transcriber

    /// 默认转录器提供者
    ///
    /// Apple 实时预览 + gpt-transcribe 终稿，地址与密钥由运行时配置提供。
    /// 云端配置不完整时回退 `.appleSpeech` 并输出配置告警。
    static let defaultTranscriberProvider: TranscriberProvider = .hybridWhisper
    /// 默认 provider（当用户未在设置中显式选择时）
    static let defaultProvider: LLMProviderType = .azureFoundry

    /// Azure Foundry 配置
    ///
    /// `azureEndpoint`：从环境变量 `AZURE_FOUNDRY_ENDPOINT` 读取；
    /// 未配置时尝试 `AZURE_OPENAI_ENDPOINT`，两者都缺失则 Azure 不可用。
    /// `azureModelIdentifier`：可通过 `AZURE_FOUNDRY_MODEL` 覆盖。
    static var azureEndpoint: URL? {
        secureURL(runtimeEnvironment["AZURE_FOUNDRY_ENDPOINT"] ?? runtimeEnvironment["AZURE_OPENAI_ENDPOINT"])
    }
    static var azureModelIdentifier: String {
        nonempty(runtimeEnvironment["AZURE_FOUNDRY_MODEL"]) ?? "gpt-5.6-luna"
    }
    static let azureAPIVersion = "2024-05-01-preview"
    static let azureAuthMode: AzureFoundryAuthMode = .apiKey
    static let azureAPIStyle: AzureFoundryAPIStyle = .openAIV1

    static func transcriptionConfig(environment: [String: String]) -> AzureWhisperConfig? {
        guard let key = nonempty(environment["AZURE_API_KEY"]) ?? nonempty(environment["whisperkey"]) else { return nil }
        if let explicit = environment["AZURE_TRANSCRIPTION_ENDPOINT"] {
            guard let endpoint = secureURL(explicit) else { return nil }
            return AzureWhisperConfig(endpoint: endpoint, apiKey: key)
        }
        guard var endpoint = secureURL(environment["AZURE_OPENAI_ENDPOINT"]),
              endpoint.path.isEmpty || endpoint.path == "/" else { return nil }
        let deployment = nonempty(environment["AZURE_TRANSCRIPTION_DEPLOYMENT"]) ?? "gpt-transcribe"
        guard deployment.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil else { return nil }
        endpoint.appendPathComponent("openai/deployments/\(deployment)/audio/transcriptions")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "api-version", value: "2024-02-01")]
        guard let url = components?.url else { return nil }
        return AzureWhisperConfig(endpoint: url, apiKey: key)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func refinementAPIKey(environment: [String: String]) -> String? {
        ["AZURE_API_KEY", "kimikey", "VOX_AZURE_FOUNDRY_API_KEY"]
            .compactMap { nonempty(environment[$0]) }.first
    }

    private static func secureURL(_ raw: String?) -> URL? {
        guard let raw = nonempty(raw), let url = URL(string: raw), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }
    
    /// 保留既有本地意图/语气分析路由，精炼使用当前 provider。
    static let analysisProviderOverrides: [AnalysisStep: LLMProviderType] = [.intent: .appleIntelligence, .tone: .appleIntelligence]

    static func analysisOptions() -> [String: String] {
        var options: [String: String] = [:]
        for (step, provider) in analysisProviderOverrides {
            options["analysis.\(step.rawValue).provider"] = provider.rawValue
        }
        return options
    }
}
