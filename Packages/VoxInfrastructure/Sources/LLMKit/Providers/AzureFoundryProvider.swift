import Foundation
import CoreModels
import Observability

/// Azure Foundry 鉴权模式
public enum AzureFoundryAuthMode: String, Sendable {
    case bearer
    case apiKey = "api-key"
}

/// Azure Foundry 部署配置（可直接配置模型、URL、API Key）
public struct AzureFoundryDeployment: Sendable, Equatable {
    public let name: String
    public let endpoint: URL
    public let model: String
    public let apiKey: String
    public let apiVersion: String
    public let authMode: AzureFoundryAuthMode
    public let maxTokens: Int
    public let topP: Double
    public let presencePenalty: Double

    public init(
        name: String,
        endpoint: URL,
        model: String,
        apiKey: String,
        apiVersion: String = "2024-05-01-preview",
        authMode: AzureFoundryAuthMode = .bearer,
        maxTokens: Int = 2048,
        topP: Double = 0.1,
        presencePenalty: Double = 0
    ) {
        self.name = name
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.apiVersion = apiVersion
        self.authMode = authMode
        self.maxTokens = maxTokens
        self.topP = topP
        self.presencePenalty = presencePenalty
    }

    public var providerConfig: LLMProviderConfig {
        LLMProviderConfig(
            providerType: .azureFoundry,
            apiKey: apiKey,
            baseURL: endpoint,
            modelIdentifier: model,
            options: [
                "azure.api_version": apiVersion,
                "azure.auth_mode": authMode.rawValue,
                "azure.max_tokens": String(maxTokens),
                "azure.top_p": String(topP),
                "azure.presence_penalty": String(presencePenalty)
            ]
        )
    }
}

/// Azure AI Foundry 远端 LLM provider。
///
/// 通过项目 endpoint 调用 chat completions 接口，支持通用 completion 与 intent/tone 分析。
public actor AzureFoundryProvider: LLMProvider {

    public nonisolated let providerType: LLMProviderType = .azureFoundry
    public nonisolated let config: LLMProviderConfig

    private let logger: Logger
    private let session: URLSession

    public init(
        config: LLMProviderConfig,
        logger: Logger? = nil,
        session: URLSession = .shared
    ) {
        self.config = config
        self.logger = logger ?? PrintLogger(subsystem: "AzureFoundry", minimumLevel: .debug)
        self.session = session
    }

    public init(
        deployment: AzureFoundryDeployment,
        logger: Logger? = nil,
        session: URLSession = .shared
    ) {
        self.init(config: deployment.providerConfig, logger: logger, session: session)
    }

    public nonisolated var isAvailable: Bool {
        config.baseURL != nil && !(config.apiKey?.isEmpty ?? true)
    }

    public func validate() async throws {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }
    }

    public nonisolated func cancel() {
        // URLSession 单次请求，当前无需维护可取消句柄
    }

    // MARK: - Completion

    public func complete(prompt: String) async throws -> String {
        try await validate()

        let instruction = "Based on the user's voice text, provide the actual needed text. Output only the processed text without any explanation."
        let response = try await requestChatCompletion(
            userPrompt: prompt,
            instruction: instruction,
            temperature: 0.2
        )
        return response
    }

    public func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let value = try await self.complete(prompt: prompt)
                    continuation.yield(value)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Analysis

    public func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis {
        try await validate()
        guard !steps.isEmpty else { return PartialAnalysis() }

        var result = PartialAnalysis()

        let intentRelatedSteps = steps.intersection([.intent, .entities, .tags, .params])
        if !intentRelatedSteps.isEmpty {
            let intent = try await analyzeIntent(request.text)
            if steps.contains(.intent) { result.intent = intent }
            if steps.contains(.entities) { result.entities = intent.entities }
            if steps.contains(.tags) { result.tags = intent.tags }
            if steps.contains(.params) { result.params = intent.params }
        }

        if steps.contains(.tone) {
            result.tone = try await analyzeTone(request.text)
        }

        return result
    }

    // MARK: - Refinement

    public func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        let refined = try await complete(prompt: request.text)
        return RefinementResponse(
            originalText: request.text,
            refinedText: refined,
            intentAnalysis: .init(),
            toneAnalysis: .init(),
            missingAnalysisSteps: Set(AnalysisStep.allCases)
        )
    }

    public func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        try await completeStreaming(prompt: request.text)
    }

    // MARK: - Internal helpers

    private struct ChatCompletionRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let max_tokens: Int
        let temperature: Double
        let top_p: Double
        let presence_penalty: Double
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                struct ContentItem: Decodable {
                    let type: String?
                    let text: String?
                }

                let content: String?
                let contents: [ContentItem]?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private func requestChatCompletion(
        userPrompt: String,
        instruction: String,
        temperature: Double
    ) async throws -> String {
        guard let baseURL = config.baseURL else {
            throw VoxError.llmProviderNotConfigured
        }
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw VoxError.llmProviderNotConfigured
        }

        let endpoint = buildCompletionsURL(from: baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authMode = Self.resolveAuthMode(endpoint: endpoint, options: config.options)
        switch authMode {
        case .apiKey:
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload = ChatCompletionRequest(
            model: config.modelIdentifier,
            messages: [
                .init(role: "system", content: instruction),
                .init(role: "user", content: userPrompt)
            ],
            max_tokens: Self.maxTokens(from: config.options),
            temperature: temperature,
            top_p: Self.topP(from: config.options),
            presence_penalty: Self.presencePenalty(from: config.options)
        )

        request.httpBody = try JSONEncoder().encode(payload)

        logger.log(.debug, "调用 Azure Foundry", context: [
            "endpoint": endpoint.absoluteString,
            "model": config.modelIdentifier,
            "prompt_length": userPrompt.count,
            "auth_header": authMode == .apiKey ? "api-key" : "Authorization: Bearer"
        ], file: #file, function: #function, line: #line)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoxError.llmRequestFailed(reason: "invalid_http_response")
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw VoxError.llmInvalidAPIKey
            }
            if http.statusCode == 429 {
                throw VoxError.llmQuotaExceeded
            }

            let body = String(data: data, encoding: .utf8) ?? ""
            throw VoxError.llmRequestFailed(reason: "status_\(http.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = decoded.choices.first else {
            throw VoxError.llmResponseInvalid
        }

        if let content = choice.message.content, !content.isEmpty {
            return content
        }

        if let contents = choice.message.contents {
            let merged = contents.compactMap(\.text).joined()
            if !merged.isEmpty {
                return merged
            }
        }

        throw VoxError.llmResponseInvalid
    }

    private func buildCompletionsURL(from baseURL: URL) -> URL {
        // Azure AI Foundry project endpoint:
        // https://<resource>.services.ai.azure.com/api/projects/<project>/models/chat/completions?api-version=2024-05-01-preview
        let apiVersion = config.options["azure.api_version"] ?? "2024-05-01-preview"

        var url = baseURL
        if !baseURL.path.hasSuffix("/models/chat/completions") {
            url.appendPathComponent("models")
            url.appendPathComponent("chat")
            url.appendPathComponent("completions")
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "api-version" }) {
            items.append(URLQueryItem(name: "api-version", value: apiVersion))
        }
        components.queryItems = items

        return components.url ?? url
    }

    private static func maxTokens(from options: [String: String]) -> Int {
        let fallback = 2048
        guard let raw = options["azure.max_tokens"], let value = Int(raw), value > 0 else {
            return fallback
        }
        return value
    }

    private static func topP(from options: [String: String]) -> Double {
        let fallback = 0.1
        guard let raw = options["azure.top_p"], let value = Double(raw) else {
            return fallback
        }
        return max(0, min(value, 1))
    }

    private static func presencePenalty(from options: [String: String]) -> Double {
        let fallback = 0.0
        guard let raw = options["azure.presence_penalty"], let value = Double(raw) else {
            return fallback
        }
        return value
    }

    private enum AuthMode {
        case bearer
        case apiKey
    }

    private static func resolveAuthMode(endpoint: URL, options: [String: String]) -> AuthMode {
        if let raw = options["azure.auth_mode"]?.lowercased() {
            if raw == AzureFoundryAuthMode.apiKey.rawValue || raw == "apikey" {
                return .apiKey
            }
            if raw == AzureFoundryAuthMode.bearer.rawValue {
                return .bearer
            }
        }

        if endpoint.path.contains("/api/projects/") {
            return .apiKey
        }
        return .bearer
    }

    private func analyzeIntent(_ text: String) async throws -> IntentAnalysis {
        let prompt = #"""
        你是一个语音意图识别助手。分析文本并返回 JSON（只输出 JSON，不要解释）。

        可能的 intent:
        self_correction, translate, polish, correct, summarize, expand, delete, plain_content

        JSON 格式：
        {
          "intent": "plain_content",
          "confidence": 0.0,
          "params": {
            "targetLanguage": null,
            "original": null,
            "corrected": null
          },
          "entities": [],
          "tags": []
        }

        文本：
        """\#(text)"""
        """#

        let raw = try await requestChatCompletion(
            userPrompt: prompt,
            instruction: "Return valid JSON only.",
            temperature: 0
        )

        let cleaned = normalizeJSON(raw)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return IntentAnalysis(intent: .plainContent, confidence: 0.5)
        }

        let intent = mapIntent(json["intent"] as? String)
        let confidence = max(0, min((json["confidence"] as? Double) ?? 0.5, 1))

        let paramsDict = json["params"] as? [String: Any]
        let params = IntentParams(
            targetLanguage: paramsDict?["targetLanguage"] as? String,
            original: paramsDict?["original"] as? String,
            corrected: paramsDict?["corrected"] as? String
        )

        let entities = (json["entities"] as? [String]) ?? []
        let tags = (json["tags"] as? [String]) ?? []

        return IntentAnalysis(
            intent: intent,
            confidence: confidence,
            params: params,
            entities: entities,
            tags: tags
        )
    }

    private func analyzeTone(_ text: String) async throws -> ToneAnalysis {
        let prompt = #"""
        你是一个语气识别助手。分析文本并返回 JSON（只输出 JSON，不要解释）。

        可能 tone: neutral, casual, formal, urgent, polite, frustrated

        JSON 格式：
        {"tone":"neutral","confidence":0.0}

        文本：
        """\#(text)"""
        """#

        let raw = try await requestChatCompletion(
            userPrompt: prompt,
            instruction: "Return valid JSON only.",
            temperature: 0
        )

        let cleaned = normalizeJSON(raw)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ToneAnalysis(tone: .neutral, confidence: 0.5)
        }

        let tone = mapTone(json["tone"] as? String)
        let confidence = max(0, min((json["confidence"] as? Double) ?? 0.5, 1))
        return ToneAnalysis(tone: tone, confidence: confidence)
    }

    private func normalizeJSON(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func mapIntent(_ raw: String?) -> IntentKind {
        switch raw?.lowercased() {
        case "self_correction":
            return .selfCorrection
        case "translate":
            return .translate
        case "polish":
            return .polish
        case "correct":
            return .correct
        case "summarize":
            return .summarize
        case "expand":
            return .expand
        case "delete":
            return .delete
        default:
            return .plainContent
        }
    }

    private func mapTone(_ raw: String?) -> ToneKind {
        switch raw?.lowercased() {
        case "neutral":
            return .neutral
        case "casual":
            return .casual
        case "formal":
            return .formal
        case "urgent":
            return .urgent
        case "polite":
            return .polite
        case "frustrated":
            return .frustrated
        default:
            return .neutral
        }
    }
}
