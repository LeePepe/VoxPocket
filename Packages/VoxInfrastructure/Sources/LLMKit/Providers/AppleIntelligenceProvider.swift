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

    /// 使用 guided generation 分析意图
    private func analyzeIntent(_ text: String, locale: Locale?) async throws -> IntentAnalysis {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        logger.debug("开始意图分析 - 文本长度: \(text.count)字符")
        let perfStart = logger.performanceStart()
        do {

            // 使用 contentTagging 专用模型
            let taggingModel = SystemLanguageModel(useCase: .contentTagging)

            let instruction = "识别文本的意图。"

            logger.log(.debug, "意图分析输入", context: [
                "text_length": text.count,
                "text_preview": String(text.prefix(200)),
                "instruction_length": instruction.count,
                "include_schema": false,
                "locale": locale?.identifier ?? "nil",
                "use_case": "contentTagging"
            ], file: #file, function: #function, line: #line)
            logger.log(.debug, "意图分析指令", context: [
                "instruction": instruction
            ], file: #file, function: #function, line: #line)
            logger.log(.debug, "意图分析提示词", context: [
                "prompt": text
            ], file: #file, function: #function, line: #line)

            let session = LanguageModelSession(
                model: taggingModel,
                tools: [],
                instructions: instruction
            )

            var latest: IntentAnalysis.PartiallyGenerated?
            var partialCount = 0
            logger.log(.debug, "意图分析选项", context: [
                "options": "default"
            ], file: #file, function: #function, line: #line)

            let stream = session.streamResponse(
                generating: IntentAnalysis.self,
                includeSchemaInPrompt: false,
                options: .init(),
                prompt: { Prompt(text) }
            )
            for try await partial in stream {
                latest = partial.content
                partialCount += 1
            }

            let intentAnalysis = IntentAnalysis(
                intent: latest?.intent ?? .plainContent,
                confidence: latest?.confidence ?? 0.0,
                params: IntentParams(
                    targetLanguage: latest?.params?.targetLanguage,
                    original: latest?.params?.original,
                    corrected: latest?.params?.corrected
                ),
                entities: latest?.entities ?? [],
                tags: latest?.tags ?? []
            )

            // 详细日志记录
            logger.log(.info, "意图分析完成", context: [
                "intent": intentAnalysis.intent.rawValue,
                "intent_confidence": intentAnalysis.confidence,
                "entities_count": intentAnalysis.entities.count,
                "entities": intentAnalysis.entities.joined(separator: ", "),
                "tags": intentAnalysis.tags.joined(separator: ", "),
                "partial_count": partialCount
            ], file: #file, function: #function, line: #line)

            logger.performanceEnd(
                "意图分析",
                start: perfStart,
                context: ["text_length": text.count],
                file: #file,
                function: #function,
                line: #line
            )
            return intentAnalysis
        } catch {
            let nsError = error as NSError
            logger.log(.error, "意图分析错误详情", context: [
                "domain": nsError.domain,
                "code": nsError.code
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

    /// 使用 guided generation 分析语气
    private func analyzeTone(_ text: String, locale: Locale?) async throws -> ToneAnalysis {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        logger.debug("开始语气分析 - 文本长度: \(text.count)字符")
        let perfStart = logger.performanceStart()
        do {
            let taggingModel = SystemLanguageModel(useCase: .contentTagging)
            let instruction = "识别文本的语气。"

            logger.log(.debug, "语气分析输入", context: [
                "text_length": text.count,
                "text_preview": String(text.prefix(200)),
                "instruction_length": instruction.count,
                "include_schema": false,
                "locale": locale?.identifier ?? "nil",
                "use_case": "contentTagging"
            ], file: #file, function: #function, line: #line)
            logger.log(.debug, "语气分析指令", context: [
                "instruction": instruction
            ], file: #file, function: #function, line: #line)
            logger.log(.debug, "语气分析提示词", context: [
                "prompt": text
            ], file: #file, function: #function, line: #line)

            let session = LanguageModelSession(
                model: taggingModel,
                tools: [],
                instructions: instruction
            )

            var latest: ToneAnalysis.PartiallyGenerated?
            var partialCount = 0
            logger.log(.debug, "语气分析选项", context: [
                "options": "default"
            ], file: #file, function: #function, line: #line)

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
                context: ["text_length": text.count],
                file: #file,
                function: #function,
                line: #line
            )
            return toneAnalysis
        } catch {
            let nsError = error as NSError
            logger.log(.error, "语气分析错误详情", context: [
                "domain": nsError.domain,
                "code": nsError.code
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

        // 阶段 1: 分析意图/语气（分别调用）
        logger.debug("启用两阶段处理：意图 → 语气 → 优化")
        let intentAnalysis = try await analyzeIntent(
            request.text,
            locale: request.transcriptionMetadata?.locale
        )
        let toneAnalysis = try await analyzeTone(
            request.text,
            locale: request.transcriptionMetadata?.locale
        )

        // 阶段 2: 构建简化 prompt
        let prompt = RefinementPromptBuilder.build(
            text: request.text,
            customPrompt: request.customPrompt
        )
        logger.log(.debug, "使用简化 prompt 进行优化", context: [
            "intent": intentAnalysis.intent.rawValue,
            "tone": toneAnalysis.tone.rawValue
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
            intentAnalysis: intentAnalysis,
            toneAnalysis: toneAnalysis,
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
