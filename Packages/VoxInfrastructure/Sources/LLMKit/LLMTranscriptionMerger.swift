import Foundation
import LokiKit
import TranscriptionKit

/// 基于 LLM 的转录结果合并器
///
/// 将 Apple Speech 和 WhisperKit 两路识别结果发送给 LLM，
/// 由模型综合两者优势输出更准确的最终文本。
public final class LLMTranscriptionMerger: TranscriptionMerger, Sendable {

    private let llmService: any LLMService
    private let logger: Logger

    public init(llmService: any LLMService, logger: Logger = PrintLogger(subsystem: "LLMTranscriptionMerger")) {
        self.llmService = llmService
        self.logger = logger
    }

    public func merge(appleSpeech: String, whisper: String) async throws -> String {
        logger.info("merge() — AppleSpeech: '\(appleSpeech)' | Whisper: '\(whisper)'")

        // 策略：以 Whisper（高精度离线）为基底，用 Apple Speech（实时）交叉校正。
        // 明确限制输出只能来自两路结果中已有的内容，防止模型自由生成。
        // 注意：避免在标签中使用会出现在候选词汇中的文字，防止 LLM 把标签当输出。
        let maxLen = max(appleSpeech.count, whisper.count)
        let prompt = """
        A: \(appleSpeech)
        B: \(whisper)

        以 B 为基础，参考 A 校正明显错字或漏字，输出最准确的语音转录文本。
        只能使用 A 和 B 中已有的词，不得添加新内容。
        输出长度不超过 \(maxLen + 5) 个字符。
        只输出转录文本本身，不输出任何标签或解释。
        """
        logger.info("merge() — Prompt: '\(prompt)'")

        let output: String
        do {
            output = try await llmService.complete(prompt: prompt)
        } catch {
            logger.error("merge() — LLM call failed: \(error). Falling back to Whisper.")
            return whisper
        }

        logger.info("merge() — LLM raw output: '\(output)'")

        // 合理性校验：输出超过较长输入的 1.5 倍视为幻觉，回退到 whisper
        guard output.count <= Int(Double(maxLen) * 1.5) else {
            logger.warning("merge() — LLM output too long (\(output.count) chars), falling back to Whisper. Output: '\(output)'")
            return whisper
        }

        logger.info("merge() — Final: '\(output)'")
        return output
    }
}
