import Foundation
import FoundationModels
import VoxCore

enum AppleIntelligenceLocaleResolver {
    static func resolve(
        _ requestedLocale: Locale?,
        supportedLanguages: [Locale.Language],
        fallback: Locale = Locale(identifier: "en-US")
    ) -> Locale {
        guard let requestedLocale else { return fallback }
        let requestedLanguage = requestedLocale.language

        // 直接比较 Locale.Language 可能误判（例如 zh-Hans vs zh），优先使用结构化字段匹配。
        if isExplicitlySupported(requestedLanguage, supportedLanguages: supportedLanguages) {
            return requestedLocale
        }

        guard let requestedCode = requestedLanguage.languageCode?.identifier else {
            return fallback
        }

        let sameLanguageCandidates = supportedLanguages.filter {
            $0.languageCode?.identifier == requestedCode
        }

        guard !sameLanguageCandidates.isEmpty else {
            return fallback
        }

        // 优先同 script，其次同 region，最后使用第一个同语种候选。
        if let requestedScript = requestedLanguage.script?.identifier {
            let sameScript = sameLanguageCandidates.filter { $0.script?.identifier == requestedScript }
            if let resolved = selectPreferredLanguage(from: sameScript, requestedLanguage: requestedLanguage) {
                return Locale(identifier: resolved.minimalIdentifier)
            }
        }

        if let resolved = selectPreferredLanguage(from: sameLanguageCandidates, requestedLanguage: requestedLanguage) {
            return Locale(identifier: resolved.minimalIdentifier)
        }

        return fallback
    }

    private static func isExplicitlySupported(
        _ requestedLanguage: Locale.Language,
        supportedLanguages: [Locale.Language]
    ) -> Bool {
        let requestedKey = languageKey(requestedLanguage)
        let requestedMinimal = requestedLanguage.minimalIdentifier
        return supportedLanguages.contains {
            languageKey($0) == requestedKey || $0.minimalIdentifier == requestedMinimal
        }
    }

    private static func selectPreferredLanguage(
        from candidates: [Locale.Language],
        requestedLanguage: Locale.Language
    ) -> Locale.Language? {
        guard !candidates.isEmpty else { return nil }
        if let requestedRegion = requestedLanguage.region?.identifier,
           let sameRegion = candidates.first(where: { $0.region?.identifier == requestedRegion }) {
            return sameRegion
        }
        if let noRegion = candidates.first(where: { $0.region == nil }) {
            return noRegion
        }
        return candidates.first
    }

    private static func languageKey(_ language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? ""
        let script = language.script?.identifier ?? ""
        let region = language.region?.identifier ?? ""
        return "\(code)|\(script)|\(region)"
    }
}

/// Apple Intelligence LLM 提供者
///
/// 使用 `FoundationModels` 框架的设备端语言模型进行文本优化。
public actor AppleIntelligenceProvider: LLMProvider {

    public nonisolated let providerType: LLMProviderType = .appleIntelligence
    public nonisolated let config: LLMProviderConfig
    private let logger: any VoxLogger

    public init(
        config: LLMProviderConfig = LLMProviderConfig(
            providerType: .appleIntelligence,
            modelIdentifier: "apple-intelligence"
        ),
        logger: (any VoxLogger)? = nil
    ) {
        self.config = config
        self.logger = logger ?? NoopVoxLogger()
    }

    // MARK: - LLMProvider

    public nonisolated var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    // MARK: - 通用文本完成

    public func complete(prompt: String) async throws -> String {
        guard isAvailable else {
            throw VoxKitError.llmProviderNotConfigured
        }

        // 使用英文指令以确保兼容性
        let session = LanguageModelSession(
            model: .default,
            tools: [],
            instructions: "Based on the user's voice text, provide the actual needed text. Output only the processed text without any explanation."
        )
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - Locale Support

    /// 验证并获取支持的 locale，如果不支持则回退到 en-US
    private nonisolated func validateLocale(_ locale: Locale?) -> Locale {
        // 获取支持的语言列表
        let supportedLanguages = Array(SystemLanguageModel.default.supportedLanguages)
        let defaultFallback = Locale(identifier: "en-US")

        // 如果没有提供 locale，使用 en-US
        guard let locale = locale else {
            logger.debug("No locale provided, using en-US")
            return defaultFallback
        }

        let resolvedLocale = AppleIntelligenceLocaleResolver.resolve(
            locale,
            supportedLanguages: supportedLanguages,
            fallback: defaultFallback
        )

        if resolvedLocale.identifier == locale.identifier {
            logger.debug("Locale is supported")
            return resolvedLocale
        }

        if resolvedLocale.identifier == defaultFallback.identifier {
            logger.warning("Locale unsupported; falling back to en-US")
            return resolvedLocale
        }

        logger.warning("Locale not explicit; falling back to same-language locale")
        return resolvedLocale
    }

    // MARK: - Intent & Tone Analysis

    /// 使用文本完成分析意图（替代 guided generation，性能提升 100+ 倍）
    private func analyzeIntent(_ text: String, locale: Locale?) async throws -> IntentAnalysis {
        guard isAvailable else {
            throw VoxKitError.llmProviderNotConfigured
        }

        // 验证并使用支持的 locale
        let validatedLocale = validateLocale(locale)

        logger.debug("开始意图分析（文本完成模式）", fields: [.int("text_length", text.count)])
        let perfStart = Date()
        do {
            // 根据 locale 选择合适的指令语言。
            // 重要：用户文本嵌入 instructions 而非 prompt，避免 FoundationModels
            // 对短 prompt 做语言检测时，因文本含 Latin 字符而误判为非支持语言（如 ro）。
            let instruction: String
            let prompt: String
            if validatedLocale.language.languageCode?.identifier.hasPrefix("zh") == true {
                instruction = """
                你是一个语音意图识别助手。分析以下语音转录文字，识别用户的真实意图。

                待分析的文字：「\(text)」

                可能的意图类型：
                - self_correction: 将口语化内容转为准确的文字表达（默认）
                - translate: 翻译请求
                - polish: 润色文本
                - correct: 纠错
                - summarize: 总结
                - expand: 扩展内容

                请返回 JSON 格式（只输出 JSON，不要添加任何解释）：
                {"intent": "意图类型", "confidence": 0.0-1.0}
                """
                prompt = "请分析意图，返回JSON格式"
            } else {
                instruction = """
                You are a voice intent recognition assistant. Analyze the following speech transcription to identify the user's true intent.

                Text to analyze: "\(text)"

                Possible intent types:
                - self_correction: Convert colloquial speech to accurate written text (default)
                - translate: Translation request
                - polish: Polish text
                - correct: Correction
                - summarize: Summarize
                - expand: Expand content

                Return JSON format only (no explanation):
                {"intent": "intent_type", "confidence": 0.0-1.0}
                """
                prompt = "Analyze the intent and return JSON"
            }

            logger.log(.debug, "意图分析配置", fields: [.int("text_length", text.count)])

            let session = LanguageModelSession(
                model: .default,
                tools: [],
                instructions: instruction
            )

            let response = try await session.respond(to: prompt)
            var jsonText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // 移除 markdown JSON 包裹（如果有）
            if jsonText.hasPrefix("```json") || jsonText.hasPrefix("```") {
                jsonText = jsonText.replacingOccurrences(of: "```json", with: "")
                jsonText = jsonText.replacingOccurrences(of: "```", with: "")
                jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            logger.log(.debug, "收到 LLM 响应（已清理）", fields: [.int("response_length", jsonText.count)])

            // 解析 JSON
            guard let data = jsonText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let intentStr = json["intent"] as? String,
                  let confidence = json["confidence"] as? Double else {
                logger.log(.warning, "JSON 解析失败，使用默认值", fields: [])
                return IntentAnalysis(intent: .selfCorrection, confidence: 0.5, params: IntentParams(), entities: [], tags: [])
            }

            // 映射意图类型
            let intent: IntentKind
            switch intentStr.lowercased() {
            case "translate":
                intent = .translate
            case "polish":
                intent = .polish
            case "correct":
                intent = .correct
            case "summarize":
                intent = .summarize
            case "expand":
                intent = .expand
            default:
                intent = .selfCorrection
            }

            let result = IntentAnalysis(
                intent: intent,
                confidence: confidence,
                params: IntentParams(),
                entities: [],
                tags: []
            )

            logger.log(.info, "意图分析完成", fields: [])

            logger.log(.info, "意图分析 (文本完成)", fields: [.int("text_length", text.count), .durationMs("duration_ms", Date().timeIntervalSince(perfStart) * 1000)])

            return result
        } catch {
            logger.log(.error, "意图分析失败", fields: [])

            logger.log(.info, "意图分析 (文本完成)", fields: [.int("text_length", text.count), .durationMs("duration_ms", Date().timeIntervalSince(perfStart) * 1000)])

            throw error
        }
    }

    /// 使用文本完成分析语气（替代 guided generation，性能提升 100+ 倍）
    private func analyzeTone(_ text: String, locale: Locale?) async throws -> ToneAnalysis {
        guard isAvailable else {
            throw VoxKitError.llmProviderNotConfigured
        }

        // 验证并使用支持的 locale
        let validatedLocale = validateLocale(locale)

        logger.debug("开始语气分析（文本完成模式）", fields: [.int("text_length", text.count)])
        let perfStart = Date()
        do {
            // 根据 locale 选择合适的指令语言。
            // 重要：用户文本嵌入 instructions 而非 prompt，避免 FoundationModels
            // 对短 prompt 做语言检测时，因文本含 Latin 字符而误判为非支持语言（如 ro）。
            let instruction: String
            let prompt: String
            if validatedLocale.language.languageCode?.identifier.hasPrefix("zh") == true {
                instruction = """
                你是一个语气识别助手。分析以下文字的语气。

                待分析的文字：「\(text)」

                可能的语气类型：
                - neutral: 中性
                - casual: 随意
                - formal: 正式
                - urgent: 紧急
                - polite: 礼貌
                - frustrated: 沮丧

                请返回 JSON 格式（只输出 JSON，不要添加任何解释）：
                {"tone": "语气类型", "confidence": 0.0-1.0}
                """
                prompt = "请分析语气，返回JSON格式"
            } else {
                instruction = """
                You are a tone analysis assistant. Analyze the tone of the following text.

                Text to analyze: "\(text)"

                Possible tone types:
                - neutral
                - casual
                - formal
                - urgent
                - polite
                - frustrated

                Return JSON format only (no explanation):
                {"tone": "tone_type", "confidence": 0.0-1.0}
                """
                prompt = "Analyze the tone and return JSON"
            }

            logger.log(.debug, "语气分析配置", fields: [.int("text_length", text.count)])

            let session = LanguageModelSession(
                model: .default,
                tools: [],
                instructions: instruction
            )

            let response = try await session.respond(to: prompt)
            var jsonText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // 移除 markdown JSON 包裹（如果有）
            if jsonText.hasPrefix("```json") || jsonText.hasPrefix("```") {
                jsonText = jsonText.replacingOccurrences(of: "```json", with: "")
                jsonText = jsonText.replacingOccurrences(of: "```", with: "")
                jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            logger.log(.debug, "收到 LLM 响应（已清理）", fields: [.int("response_length", jsonText.count)])

            // 解析 JSON
            guard let data = jsonText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let toneStr = json["tone"] as? String,
                  let confidence = json["confidence"] as? Double else {
                logger.log(.warning, "JSON 解析失败，使用默认值", fields: [])
                return ToneAnalysis(tone: .neutral, confidence: 0.5)
            }

            // 映射语气类型
            let tone: ToneKind
            switch toneStr.lowercased() {
            case "neutral":
                tone = .neutral
            case "casual":
                tone = .casual
            case "formal":
                tone = .formal
            case "urgent":
                tone = .urgent
            case "polite":
                tone = .polite
            case "frustrated":
                tone = .frustrated
            default:
                tone = .neutral
            }

            let result = ToneAnalysis(tone: tone, confidence: confidence)

            logger.log(.info, "语气分析完成", fields: [])

            logger.log(.info, "语气分析 (文本完成)", fields: [.int("text_length", text.count), .durationMs("duration_ms", Date().timeIntervalSince(perfStart) * 1000)])

            return result
        } catch {
            logger.log(.error, "语气分析失败", fields: [])

            logger.log(.info, "语气分析 (文本完成)", fields: [.int("text_length", text.count), .durationMs("duration_ms", Date().timeIntervalSince(perfStart) * 1000)])

            throw error
        }
    }

    // MARK: - 文本优化（便捷方法）

    public func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        guard isAvailable else {
            throw VoxKitError.llmProviderNotConfigured
        }

        logger.log(.info, "开始文本优化", fields: [.int("text_length", request.text.count)])

        // 阶段 1: 分析意图/语气（并行执行，失败时使用默认值）
        logger.debug("启用两阶段处理：意图 || 语气（并行） → 优化")
        let perfAnalysisStart = Date()

        // 使用 async let 并行执行意图和语气分析
        async let intentResult: IntentAnalysis = {
            do {
                return try await analyzeIntent(
                    request.text,
                    locale: request.transcriptionMetadata?.locale
                )
            } catch {
                logger.log(.warning, "意图分析失败，使用默认值", fields: [])
                return IntentAnalysis(intent: .selfCorrection, confidence: 0.0)
            }
        }()

        async let toneResult: ToneAnalysis = {
            do {
                return try await analyzeTone(
                    request.text,
                    locale: request.transcriptionMetadata?.locale
                )
            } catch {
                logger.log(.warning, "语气分析失败，使用默认值", fields: [])
                return ToneAnalysis(tone: .neutral, confidence: 0.0)
            }
        }()

        // 等待两个分析都完成
        let (intent, tone) = await (intentResult, toneResult)

        logger.log(.info, "并行分析 (意图 + 语气)", fields: [.int("text_length", request.text.count), .durationMs("duration_ms", Date().timeIntervalSince(perfAnalysisStart) * 1000)])

        // 阶段 2: 构建简化 prompt
        let prompt = RefinementPromptBuilder.build(
            text: request.text,
            customPrompt: request.customPrompt
        )
        logger.log(.debug, "使用简化 prompt 进行优化", fields: [])

        // 执行优化
        let refinedText = try await complete(prompt: prompt)

        logger.log(.info, "文本优化完成", fields: [.int("original_length", request.text.count), .int("refined_length", refinedText.count)])

        return RefinementResponse(
            originalText: request.text,
            refinedText: refinedText,
            intentAnalysis: intent,
            toneAnalysis: tone,
            missingAnalysisSteps: []
        )
    }

    public func validate() async throws {
        guard isAvailable else {
            throw VoxKitError.llmProviderNotConfigured
        }
    }

    public nonisolated func cancel() {
        // No-op: task cancellation removed
    }

    // MARK: - Streaming Methods

    /// 流式文本完成
    public func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else {
            throw VoxKitError.llmProviderNotConfigured
        }

        // 使用英文指令以确保兼容性
        let session = LanguageModelSession(
            model: .default,
            tools: [],
            instructions: "Based on the user's voice text, provide the actual needed text. Output only the processed text without any explanation."
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = session.streamResponse(to: prompt, options: .init())
                    // response.content 是累积的完整文本，直接返回完整内容
                    for try await response in stream {
                        continuation.yield(response.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// 流式优化（先执行 intent/tone 分析，再构建增强 prompt）
    public func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else {
            throw VoxKitError.llmProviderNotConfigured
        }

        logger.debug("流式优化：先执行意图/语气分析，再构建 prompt")
        _ = try await analyzeIntent(
            request.text,
            locale: request.transcriptionMetadata?.locale
        )
        _ = try await analyzeTone(
            request.text,
            locale: request.transcriptionMetadata?.locale
        )
        let prompt = RefinementPromptBuilder.build(
            text: request.text,
            customPrompt: request.customPrompt
        )
        return try await completeStreaming(prompt: prompt)
    }

    // MARK: - Content Analysis

    public func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis {
        guard isAvailable else {
            throw VoxKitError.llmProviderNotConfigured
        }
        guard !steps.isEmpty else {
            return PartialAnalysis()
        }

        var partial = PartialAnalysis()
        if steps.contains(.intent) || steps.contains(.entities) || steps.contains(.tags) || steps.contains(.params) {
            let intentAnalysis = try await analyzeIntent(
                request.text,
                locale: request.transcriptionMetadata?.locale
            )
            if steps.contains(.intent) {
                partial.intent = intentAnalysis
            }
            if steps.contains(.entities) {
                partial.entities = intentAnalysis.entities
            }
            if steps.contains(.tags) {
                partial.tags = intentAnalysis.tags
            }
            if steps.contains(.params) {
                partial.params = intentAnalysis.params
            }
        }
        if steps.contains(.tone) {
            let toneAnalysis = try await analyzeTone(
                request.text,
                locale: request.transcriptionMetadata?.locale
            )
            partial.tone = toneAnalysis
        }
        return partial
    }
}
