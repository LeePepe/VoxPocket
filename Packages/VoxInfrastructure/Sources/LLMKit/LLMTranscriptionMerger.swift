import Foundation
import TranscriptionKit

/// 基于 LLM 的转录结果合并器
///
/// 将 Apple Speech 和 WhisperKit 两路识别结果发送给 LLM，
/// 由模型综合两者优势输出更准确的最终文本。
public final class LLMTranscriptionMerger: TranscriptionMerger, Sendable {

    private let llmService: any LLMService

    public init(llmService: any LLMService) {
        self.llmService = llmService
    }

    public func merge(appleSpeech: String, whisper: String) async throws -> String {
        // 策略：以 Whisper（高精度离线）为基底，用 Apple Speech（实时）交叉校正。
        // 明确限制输出只能来自两路结果中已有的内容，防止模型自由生成。
        let maxLen = max(appleSpeech.count, whisper.count)
        let prompt = """
        以下是同一段语音经过两个识别器处理的结果：

        实时识别（Apple Speech）：\(appleSpeech)
        高精度识别（Whisper）：\(whisper)

        请以「高精度识别」为基础，参考「实时识别」校正其中明显的错字或漏字，输出最准确的语音内容。
        要求：
        - 只能使用两个结果中已出现的词，不得添加任何新内容
        - 输出长度不超过 \(maxLen + 5) 个字符
        - 直接输出文本，不加任何解释
        """
        let output = try await llmService.complete(prompt: prompt)

        // 合理性校验：输出超过较长输入的 1.5 倍视为幻觉，回退到 whisper
        guard output.count <= Int(Double(maxLen) * 1.5) else {
            return whisper
        }
        return output
    }
}
