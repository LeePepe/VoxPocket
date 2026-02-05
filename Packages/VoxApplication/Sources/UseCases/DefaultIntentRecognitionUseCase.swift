import Foundation
import LLMKit

/// 默认意图识别用例实现
///
/// 使用 LLM 识别用户意图：
/// 1. 如果配置了 LLM，进行深度识别
/// 2. 失败时，返回 plainContent
public final class DefaultIntentRecognitionUseCase: IntentRecognitionUseCase, Sendable {

    private let llmService: LLMService
    private let editingUseCase: EditingUseCase
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
        // 如果启用了 LLM 且配置了提供者，使用 LLM 识别
        if isLLMEnhancementEnabled, llmService.currentProvider != nil {
            do {
                let result = try await recognizeWithLLM(text: text)
                print("🤖 [Intent] LLM match: \(result.intent.displayName) (confidence: \(result.confidence))")
                return result
            } catch {
                print("⚠️ [Intent] LLM recognition failed: \(error.localizedDescription)")
                // 降级到默认行为
            }
        }

        // 默认：作为普通内容处理
        print("📝 [Intent] Default: plain content")
        return IntentRecognitionResult(intent: .plainContent, confidence: 1.0)
    }

    public func quickRecognize(from text: String) -> IntentRecognitionResult? {
        return nil
    }

    // MARK: - LLM 识别

    private func recognizeWithLLM(text: String) async throws -> IntentRecognitionResult {
        let prompt = buildIntentPrompt(text: text)
        let response = try await llmService.complete(prompt: prompt)
        return parseIntentFromLLM(response: response, originalText: text)
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
