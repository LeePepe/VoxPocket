import Foundation
import FoundationModels
import CoreModels
import Observability

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

        let session = LanguageModelSession(model: .default, tools: [], instructions: "根据用户的语音文本，给出实际需要的文本。只输出处理后的文本，不要添加任何解释。")
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - Intent & Tone Analysis

    /// 使用 guided generation 分析意图（简化版，性能优化）
    private func analyzeIntent(_ text: String, locale: Locale?) async throws -> IntentAnalysis {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        logger.debug("开始意图分析（快速模式）- 文本长度: \(text.count)字符")
        let perfStart = logger.performanceStart()
        do {
            // 使用 contentTagging 专用模型
            let taggingModel = SystemLanguageModel(useCase: .contentTagging)
            let instruction = "识别文本的意图。"

            logger.log(.debug, "意图分析输入", context: [
                "text_length": text.count,
                "text_preview": String(text.prefix(200)),
                "use_case": "contentTagging",
                "fast_mode": true
            ], file: #file, function: #function, line: #line)

            let session = LanguageModelSession(
                model: taggingModel,
                tools: [],
                instructions: instruction
            )

            // 使用简化的 FastIntentAnalysis，避免复杂的 guided generation
            // 使用简化的 FastIntentAnalysis 提高性能
            var latest: FastIntentAnalysis.PartiallyGenerated?
            var partialCount = 0

            let stream = session.streamResponse(
                generating: FastIntentAnalysis.self,
                includeSchemaInPrompt: false,
                options: .init(),
                prompt: { Prompt(text) }
            )
            for try await partial in stream {
                latest = partial.content
                partialCount += 1
            }

            let intent = latest?.intent ?? .plainContent
            let confidence = latest?.confidence ?? 0.0

            // 返回简化版结果（entities 和 tags 为空）
            let intentAnalysis = IntentAnalysis(
                intent: intent,
                confidence: confidence,
                params: IntentParams(),
                entities: [],
                tags: []
            )

            logger.log(.info, "意图分析完成", context: [
                "intent": intentAnalysis.intent.rawValue,
                "intent_confidence": intentAnalysis.confidence,
                "partial_count": partialCount
            ], file: #file, function: #function, line: #line)

            logger.performanceEnd(
                "意图分析",
                start: perfStart,
                context: ["text_length": text.count, "fast_mode": true],
                file: #file,
                function: #function,
                line: #line
            )
            return intentAnalysis
        } catch {
            let nsError = error as NSError
            logger.log(.error, "意图分析失败", context: [
                "domain": nsError.domain,
                "code": nsError.code,
                "description": error.localizedDescription
            ], file: #file, function: #function, line: #line)
            logger.performanceEnd(
                "意图分析",
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

    /// 使用 guided generation 分析语气（优化版，带超时）
    private func analyzeTone(_ text: String, locale: Locale?) async throws -> ToneAnalysis {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        logger.debug("开始语气分析（快速模式）- 文本长度: \(text.count)字符")
        let perfStart = logger.performanceStart()
        do {
            let taggingModel = SystemLanguageModel(useCase: .contentTagging)
            let instruction = "识别文本的语气。"

            logger.log(.debug, "语气分析输入", context: [
                "text_length": text.count,
                "text_preview": String(text.prefix(200)),
                "use_case": "contentTagging",
                "fast_mode": true
            ], file: #file, function: #function, line: #line)

            let session = LanguageModelSession(
                model: taggingModel,
                tools: [],
                instructions: instruction
            )

            // ToneAnalysis 本身已经是简化的 schema，直接使用
            var latest: ToneAnalysis.PartiallyGenerated?
            var partialCount = 0

            let stream = session.streamResponse(
                generating: ToneAnalysis.self,
                includeSchemaInPrompt: false,
                options: .init(),
                prompt: { Prompt(text) }
            )
            for try await partial in stream {
                latest = partial.content
                partialCount += 1
            }

            let toneAnalysis = ToneAnalysis(
                tone: latest?.tone ?? .neutral,
                confidence: latest?.confidence ?? 0.0
            )

            logger.log(.info, "语气分析完成", context: [
                "tone": toneAnalysis.tone.rawValue,
                "tone_confidence": toneAnalysis.confidence,
                "partial_count": partialCount
            ], file: #file, function: #function, line: #line)

            logger.performanceEnd(
                "语气分析",
                start: perfStart,
                context: ["text_length": text.count, "fast_mode": true],
                file: #file,
                function: #function,
                line: #line
            )
            return toneAnalysis
        } catch {
            let nsError = error as NSError
            logger.log(.error, "语气分析失败", context: [
                "domain": nsError.domain,
                "code": nsError.code,
                "description": error.localizedDescription
            ], file: #file, function: #function, line: #line)
            logger.performanceEnd(
                "语气分析",
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
                return IntentAnalysis(intent: .plainContent, confidence: 0.0)
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

        let session = LanguageModelSession(
            model: .default,
            tools: [],
            instructions: "根据用户的语音文本，给出实际需要的文本。只输出处理后的文本，不要添加任何解释。"
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = session.streamResponse(to: prompt, options: .init())
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
