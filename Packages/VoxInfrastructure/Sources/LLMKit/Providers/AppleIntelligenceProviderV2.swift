import Foundation
import FoundationModels
import CoreModels
import Observability

/// Apple Intelligence Provider V2 - 使用直接文本完成而不是 guided generation
///
/// 由于 guided generation 存在严重性能问题（超时 120+ 秒），
/// 这个版本使用传统的文本完成 + JSON 解析方式。
public actor AppleIntelligenceProviderV2 {

    private let logger: Logger

    public init(logger: Logger? = nil) {
        self.logger = logger ?? PrintLogger(subsystem: "AppleIntelligenceV2", minimumLevel: .debug)
    }

    public nonisolated var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    /// 使用普通文本完成分析意图（不使用 guided generation）
    public func analyzeIntent(_ text: String, locale: Locale?) async throws -> IntentAnalysis {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        logger.debug("开始意图分析（文本完成模式）- 文本长度: \(text.count)字符")
        let perfStart = logger.performanceStart()

        do {
            // 使用 default 模型进行文本完成
            let instruction = """
            你是一个语音意图识别助手。分析用户的语音转录文本，识别用户的真实意图。

            可能的意图类型：
            - self_correction: 用户自我纠正（如"不对，应该是..."）
            - translate: 翻译请求
            - polish: 润色文本
            - correct: 纠错
            - summarize: 总结
            - expand: 扩展内容
            - delete: 删除/撤销
            - plain_content: 普通内容（默认）

            请返回 JSON 格式（只输出 JSON，不要添加任何解释）：
            {"intent": "意图类型", "confidence": 0.0-1.0}
            """

            logger.log(.debug, "意图分析配置", context: [
                "text_length": text.count,
                "method": "text_completion",
                "model": "default"
            ], file: #file, function: #function, line: #line)

            let session = LanguageModelSession(
                model: .default,
                tools: [],
                instructions: instruction
            )

            let response = try await session.respond(to: text)
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
                return IntentAnalysis(intent: .plainContent, confidence: 0.5)
            }

            // 映射意图类型
            let intent: IntentKind
            switch intentStr.lowercased() {
            case "self_correction":
                intent = .selfCorrection
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
            case "delete":
                intent = .delete
            default:
                intent = .plainContent
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
                "confidence": result.confidence
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

    /// 使用普通文本完成分析语气（不使用 guided generation）
    public func analyzeTone(_ text: String, locale: Locale?) async throws -> ToneAnalysis {
        guard isAvailable else {
            throw VoxError.llmProviderNotConfigured
        }

        logger.debug("开始语气分析（文本完成模式）- 文本长度: \(text.count)字符")
        let perfStart = logger.performanceStart()

        do {
            let instruction = """
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

            logger.log(.debug, "语气分析配置", context: [
                "text_length": text.count,
                "method": "text_completion"
            ], file: #file, function: #function, line: #line)

            let session = LanguageModelSession(
                model: .default,
                tools: [],
                instructions: instruction
            )

            let response = try await session.respond(to: text)
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
                "confidence": result.confidence
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
}
