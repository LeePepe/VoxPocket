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
        // 让模型"选择"更准确的一个，而非"合成"——防止模型自由发挥产生幻觉
        let prompt = """
        以下是对同一段语音的两条识别结果，请选择其中更准确、更完整的一条，原文输出，不做任何增删改动：

        结果A：\(appleSpeech)
        结果B：\(whisper)
        """
        let output = try await llmService.complete(prompt: prompt)

        // 合理性校验：若输出长度超过两个输入中较长者的 1.5 倍，视为幻觉，回退到 whisper
        let maxInputLength = max(appleSpeech.count, whisper.count)
        guard output.count <= Int(Double(maxInputLength) * 1.5) else {
            return whisper
        }
        return output
    }
}
