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
        let prompt = """
        你是语音识别结果合并专家。以下是两个识别器对同一段语音的识别结果：

        识别器1（Apple Speech，快速实时）：
        \(appleSpeech)

        识别器2（Whisper，高精度离线）：
        \(whisper)

        请综合两个识别结果，输出最准确的最终文本。保留原始语言，直接输出文本内容，不要添加任何解释或前缀。
        """
        return try await llmService.complete(prompt: prompt)
    }
}
