import Foundation
import LLMKit
import Observability

/// 默认意图识别用例实现
///
/// 使用 LLM 识别用户意图：
/// 1. 如果配置了 LLM，进行深度识别
/// 2. 失败时，返回 plainContent
public final class DefaultIntentRecognitionUseCase: IntentRecognitionUseCase, Sendable {

    private let llmService: LLMService
    private let editingUseCase: EditingUseCase
    private let logger = PrintLogger(subsystem: "IntentRecognition", minimumLevel: .debug)
    public let isLLMEnhancementEnabled: Bool

    public init(
        llmService: LLMService,
        editingUseCase: EditingUseCase,
        isLLMEnhancementEnabled: Bool = true
    ) {
        self.llmService = llmService
        self.editingUseCase = editingUseCase
        self.isLLMEnhancementEnabled = isLLMEnhancementEnabled
    }

    // MARK: - IntentRecognitionUseCase

    public func recognizeIntent(from text: String) async throws -> IntentRecognitionResult {
        logger.log(.debug, "开始意图识别", context: [
            "text_length": text.count,
            "text_preview": String(text.prefix(100)),
            "llm_enabled": isLLMEnhancementEnabled,
            "has_provider": llmService.currentProvider != nil
        ], file: #file, function: #function, line: #line)

        let perfStart = logger.performanceStart()

        // 如果启用了 LLM 且配置了提供者，使用 LLM 识别
        if isLLMEnhancementEnabled, llmService.currentProvider != nil {
            do {
                let result = try await recognizeWithLLM(text: text)

                logger.log(.info, "意图识别成功 (LLM)", context: [
                    "intent": result.intent.displayName,
                    "confidence": result.confidence,
                    "text_length": text.count
                ], file: #file, function: #function, line: #line)

                logger.performanceEnd(
                    "意图识别 (LLM)",
                    start: perfStart,
                    context: ["text_length": text.count, "intent": result.intent.displayName],
                    file: #file,
                    function: #function,
                    line: #line
                )

                return result
            } catch {
                logger.log(.warning, "意图识别失败，降级到默认行为", context: [
                    "error": error.localizedDescription,
                    "text_length": text.count
                ], file: #file, function: #function, line: #line)

                logger.performanceEnd(
                    "意图识别 (fallback)",
                    start: perfStart,
                    context: ["text_length": text.count],
                    error: error,
                    file: #file,
                    function: #function,
                    line: #line
                )
                // 降级到默认行为
            }
        }

        // 默认：作为普通内容处理
        logger.log(.info, "使用默认意图", context: [
            "intent": "plain_content",
            "reason": isLLMEnhancementEnabled ? "no_provider" : "llm_disabled"
        ], file: #file, function: #function, line: #line)

        logger.performanceEnd(
            "意图识别 (default)",
            start: perfStart,
            context: ["text_length": text.count],
            file: #file,
            function: #function,
            line: #line
        )

        return IntentRecognitionResult(intent: .plainContent, confidence: 1.0)
    }

    public func quickRecognize(from text: String) -> IntentRecognitionResult? {
        return nil
    }

    // MARK: - LLM 识别

    private func recognizeWithLLM(text: String) async throws -> IntentRecognitionResult {
        logger.log(.debug, "构建意图识别提示词", context: [
            "text_length": text.count
        ], file: #file, function: #function, line: #line)

        let perfPromptStart = logger.performanceStart()
        let prompt = buildIntentPrompt(text: text)
        logger.performanceEnd(
            "构建提示词",
            start: perfPromptStart,
            context: ["prompt_length": prompt.count],
            file: #file,
            function: #function,
            line: #line
        )

        logger.log(.debug, "调用 LLM 服务", context: [
            "prompt_length": prompt.count,
            "text_length": text.count
        ], file: #file, function: #function, line: #line)

        let perfLLMStart = logger.performanceStart()
        let response = try await llmService.complete(prompt: prompt)
        logger.performanceEnd(
            "LLM 调用",
            start: perfLLMStart,
            context: ["response_length": response.count],
            file: #file,
            function: #function,
            line: #line
        )

        logger.log(.debug, "解析 LLM 响应", context: [
            "response_length": response.count,
            "response_preview": String(response.prefix(200))
        ], file: #file, function: #function, line: #line)

        let perfParseStart = logger.performanceStart()
        let result = parseIntentFromLLM(response: response, originalText: text)
        logger.performanceEnd(
            "解析响应",
            start: perfParseStart,
            context: [
                "intent": result.intent.displayName,
                "confidence": result.confidence
            ],
            file: #file,
            function: #function,
            line: #line
        )

        return result
    }

    private func buildIntentPrompt(text: String) -> String {
        """
        你是一个语音意图识别助手。分析用户的语音转录文本，识别用户的真实意图。

        重要提示：
        - 如果文本包含明确的操作指令（如"翻译"、"润色"等），即使后面跟着内容，也应识别为操作意图
        - 例如："翻译成英语今天是周二" 应识别为 translate 意图（高置信度 0.9）
        - 例如："润色一下这段文字" 应识别为 polish 意图（高置信度 0.9）

        可能的意图类型：
        1. translate - 用户想翻译内容
           - 关键词：翻译、translate、翻译成、译成、英文、中文、日文等
           - 如果包含这些关键词，置信度应该 >= 0.85
        2. polish - 用户想润色内容
           - 关键词：润色、改善、优化、美化
           - 如果包含这些关键词，置信度应该 >= 0.85
        3. correct - 用户想纠错
           - 关键词：纠错、改错、修正
        4. summarize - 用户想总结
           - 关键词：总结、摘要、概括
        5. expand - 用户想扩展
           - 关键词：扩展、详细、展开
        6. self_correction - 用户自我纠正
           - 模式："A 不对 B"、"不是 A 是 B"、"应该是 A"
        7. deletion - 用户否定删除
           - 关键词：不是、删掉、不要、算了等（带有否定情绪）
        8. plain_content - 普通内容
           - 只有当完全没有任何操作意图时才选择此项

        用户输入："\(text)"

        请返回 JSON 格式（只输出 JSON，不要添加任何解释）：
        {
          "intent": "意图类型",
          "confidence": 0.0-1.0,
          "params": {
            "original": "原内容（仅 self_correction）",
            "corrected": "修正后内容（仅 self_correction）",
            "targetLanguage": "目标语言代码（仅 translate，如：en/zh/ja）"
          }
        }
        """
    }

    private func parseIntentFromLLM(response: String, originalText: String) -> IntentRecognitionResult {
        // 尝试解析 JSON 响应
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let intentStr = json["intent"] as? String,
              let confidence = json["confidence"] as? Double else {
            // 解析失败，返回默认
            return IntentRecognitionResult(intent: .plainContent, confidence: 0.5)
        }

        let params = json["params"] as? [String: String] ?? [:]

        let intent: UserIntent
        switch intentStr.lowercased() {
        case "translate":
            let targetLang = params["targetLanguage"]
            intent = .contentOperation(.translate, targetLanguage: targetLang)

        case "polish":
            intent = .contentOperation(.polish)

        case "correct":
            intent = .contentOperation(.correct)

        case "summarize":
            intent = .contentOperation(.summarize)

        case "expand":
            intent = .contentOperation(.expand)

        case "self_correction":
            let original = params["original"] ?? ""
            let corrected = params["corrected"] ?? ""
            intent = .selfCorrection(original: original, corrected: corrected)

        case "deletion":
            intent = .deletion

        default:
            intent = .plainContent
        }

        return IntentRecognitionResult(intent: intent, confidence: confidence)
    }
}
