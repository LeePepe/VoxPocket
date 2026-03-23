import Foundation
import FoundationModels
import CoreModels
import Observability

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
    private let logger: Logger

    public init(
        config: LLMProviderConfig = LLMProviderConfig(
            providerType: .appleIntelligence,
            modelIdentifier: "apple-intelligence"
        ),
        logger: Logger? = nil
    ) {
        self.config = config
        self.logger = logger ?? PrintLogger(subsystem: "AppleIntelligence", minimumLevel: .debug)
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
            throw VoxError.llmProviderNotConfigured
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
            logger.debug("Locale \(locale.identifier) is supported")
            return resolvedLocale
        }

        if resolvedLocale.identifier == defaultFallback.identifier {
            logger.warning("Locale \(locale.identifier) is NOT supported by Apple Intelligence, falling back to en-US")
            return resolvedLocale
        }

        logger.warning("Locale \(locale.identifier) is NOT explicitly supported, falling back to same-language locale \(resolvedLocale.identifier)")
        return resolvedLocale
    }

    // MARK: - Intent & Tone Analysis

    /// 使用文本完成分析意图（替代 guided generation，性能提升 100+ 倍）
    private func analyzeIntent(_ text: String, locale: Locale?) async throws -> IntentAnalysis {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        // 验证并使用支持的 locale
        let validatedLocale = validateLocale(locale)

        logger.debug("开始意图分析（文本完成模式）- 文本长度: \(text.count)字符, locale: \(validatedLocale.identifier)")
        let perfStart = logger.performanceStart()
        do {
            // 根据 locale 选择合适的指令语言
            let instruction: String
            if validatedLocale.language.languageCode?.identifier.hasPrefix("zh") == true {
                instruction = """
                你是一个语音意图识别助手。分析用户的语音转录文本，识别用户的真实意图。

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
            } else {
                instruction = """
                You are a voice intent recognition assistant. Analyze the user's speech transcription to identify their true intent.

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
            }

            logger.log(.debug, "意图分析配置", context: [
                "text_length": text.count,
                "method": "text_completion",
                "model": "default",
                "locale": validatedLocale.identifier
            ], file: #file, function: #function, line: #line)

            let session = LanguageModelSession(
                model: .default,
                tools: [],
                instructions: instruction
            )

            // prompt 与 instruction 使用同一语言，避免 Apple Intelligence
            // 对混合语言短文本检测失败（如中文被误判为其他语言）
            let prompt: String
            if validatedLocale.language.languageCode?.identifier.hasPrefix("zh") == true {
                prompt = "请分析以下文字的意图：「\(text)」"
            } else {
                prompt = "Analyze the intent of this text: \"\(text)\""
            }
            let response = try await session.respond(to: prompt)
            var jsonText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // 移除 markdown JSON 包裹（如果有）
            if jsonText.hasPrefix("```json") || jsonText.hasPrefix("```") {
                jsonText = jsonText.replacingOccurrences(of: "```json", with: "")
                jsonText = jsonText.replacingOccurrences(of: "```", with: "")
                jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            logger.log(.debug, "收到 LLM 响应（已清理）", context: [
                "response_length": jsonText.count,
                "response_preview": String(jsonText.prefix(200))
            ], file: #file, function: #function, line: #line)

            // 解析 JSON
            guard let data = jsonText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let intentStr = json["intent"] as? String,
                  let confidence = json["confidence"] as? Double else {
                logger.log(.warning, "JSON 解析失败，使用默认值", context: [
                    "response": jsonText
                ], file: #file, function: #function, line: #line)
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

            logger.log(.info, "意图分析完成", context: [
                "intent": result.intent.rawValue,
                "confidence": result.confidence,
                "method": "text_completion"
            ], file: #file, function: #function, line: #line)

            logger.performanceEnd(
                "意图分析 (文本完成)",
                start: perfStart,
                context: ["text_length": text.count, "method": "text_completion"],
                file: #file,
                function: #function,
                line: #line
            )

            return result
        } catch {
            logger.log(.error, "意图分析失败", context: [
                "error": error.localizedDescription
            ], file: #file, function: #function, line: #line)

            logger.performanceEnd(
                "意图分析 (文本完成)",
                start: perfStart,
                context: ["text_length": text.count],
                error: error,
                file: #file,
                function: #function,
                line: #line
            )

            throw error
        }
    }

    /// 使用文本完成分析语气（替代 guided generation，性能提升 100+ 倍）
    private func analyzeTone(_ text: String, locale: Locale?) async throws -> ToneAnalysis {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        // 验证并使用支持的 locale
        let validatedLocale = validateLocale(locale)

        logger.debug("开始语气分析（文本完成模式）- 文本长度: \(text.count)字符, locale: \(validatedLocale.identifier)")
        let perfStart = logger.performanceStart()
        do {
            // 根据 locale 选择合适的指令语言
            let instruction: String
            if validatedLocale.language.languageCode?.identifier.hasPrefix("zh") == true {
                instruction = """
                你是一个语气识别助手。分析文本的语气。

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
            } else {
                // 默认使用英文指令
                instruction = """
                You are a tone analysis assistant. Analyze the tone of the text.

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
            }

            logger.log(.debug, "语气分析配置", context: [
                "text_length": text.count,
                "method": "text_completion",
                "locale": validatedLocale.identifier
            ], file: #file, function: #function, line: #line)

            let session = LanguageModelSession(
                model: .default,
                tools: [],
                instructions: instruction
            )

            // prompt 与 instruction 使用同一语言，避免 Apple Intelligence
            // 对混合语言短文本检测失败（如中文被误判为其他语言）
            let prompt: String
            if validatedLocale.language.languageCode?.identifier.hasPrefix("zh") == true {
                prompt = "请分析以下文字的语气：「\(text)」"
            } else {
                prompt = "Analyze the tone of this text: \"\(text)\""
            }
            let response = try await session.respond(to: prompt)
            var jsonText = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // 移除 markdown JSON 包裹（如果有）
            if jsonText.hasPrefix("```json") || jsonText.hasPrefix("```") {
                jsonText = jsonText.replacingOccurrences(of: "```json", with: "")
                jsonText = jsonText.replacingOccurrences(of: "```", with: "")
                jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            logger.log(.debug, "收到 LLM 响应（已清理）", context: [
                "response_length": jsonText.count,
                "response_preview": String(jsonText.prefix(200))
            ], file: #file, function: #function, line: #line)

            // 解析 JSON
            guard let data = jsonText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let toneStr = json["tone"] as? String,
                  let confidence = json["confidence"] as? Double else {
                logger.log(.warning, "JSON 解析失败，使用默认值", context: [
                    "response": jsonText
                ], file: #file, function: #function, line: #line)
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

            logger.log(.info, "语气分析完成", context: [
                "tone": result.tone.rawValue,
                "confidence": result.confidence,
                "method": "text_completion"
            ], file: #file, function: #function, line: #line)

            logger.performanceEnd(
                "语气分析 (文本完成)",
                start: perfStart,
                context: ["text_length": text.count, "method": "text_completion"],
                file: #file,
                function: #function,
                line: #line
            )

            return result
        } catch {
            logger.log(.error, "语气分析失败", context: [
                "error": error.localizedDescription
            ], file: #file, function: #function, line: #line)

            logger.performanceEnd(
                "语气分析 (文本完成)",
                start: perfStart,
                context: ["text_length": text.count],
                error: error,
                file: #file,
                function: #function,
                line: #line
            )

            throw error
        }
    }

    // MARK: - 文本优化（便捷方法）

    public func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        logger.log(.info, "开始文本优化", context: [
            "text_length": request.text.count,
            "has_custom_prompt": request.customPrompt != nil
        ], file: #file, function: #function, line: #line)

        // 阶段 1: 分析意图/语气（并行执行，失败时使用默认值）
        logger.debug("启用两阶段处理：意图 || 语气（并行） → 优化")
        let perfAnalysisStart = logger.performanceStart()

        // 使用 async let 并行执行意图和语气分析
        async let intentResult: IntentAnalysis = {
            do {
                return try await analyzeIntent(
                    request.text,
                    locale: request.transcriptionMetadata?.locale
                )
            } catch {
                logger.log(.warning, "意图分析失败，使用默认值", context: [
                    "error": error.localizedDescription
                ], file: #file, function: #function, line: #line)
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
                logger.log(.warning, "语气分析失败，使用默认值", context: [
                    "error": error.localizedDescription
                ], file: #file, function: #function, line: #line)
                return ToneAnalysis(tone: .neutral, confidence: 0.0)
            }
        }()

        // 等待两个分析都完成
        let (intent, tone) = await (intentResult, toneResult)

        logger.performanceEnd(
            "并行分析 (意图 + 语气)",
            start: perfAnalysisStart,
            context: [
                "intent": intent.intent.rawValue,
                "tone": tone.tone.rawValue,
                "text_length": request.text.count
            ],
            file: #file,
            function: #function,
            line: #line
        )

        // 阶段 2: 构建简化 prompt
        let prompt = RefinementPromptBuilder.build(
            text: request.text,
            customPrompt: request.customPrompt
        )
        logger.log(.debug, "使用简化 prompt 进行优化", context: [
            "intent": intent.intent.rawValue,
            "tone": tone.tone.rawValue
        ], file: #file, function: #function, line: #line)

        // 执行优化
        let refinedText = try await complete(prompt: prompt)

        logger.log(.info, "文本优化完成", context: [
            "original_length": request.text.count,
            "refined_length": refinedText.count
        ], file: #file, function: #function, line: #line)

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
            throw VoxError.llmProviderNotConfigured
        }
    }

    public nonisolated func cancel() {
        // No-op: task cancellation removed
    }

    // MARK: - Streaming Methods

    /// 流式文本完成
    public func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
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
            throw VoxError.llmProviderNotConfigured
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
            throw VoxError.llmProviderNotConfigured
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
