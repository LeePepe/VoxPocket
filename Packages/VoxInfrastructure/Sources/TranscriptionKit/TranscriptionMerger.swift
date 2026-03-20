import Foundation

/// 多识别器结果合并器协议
///
/// 当 Transcriber 同时运行多个识别器时（如 Apple Speech + WhisperKit），
/// 可通过此协议将两路结果交给 LLM 合并，得到比任何单一识别器更准确的最终文本。
public protocol TranscriptionMerger: Sendable {

    /// 合并两路识别结果
    ///
    /// - Parameters:
    ///   - appleSpeech: Apple Speech 识别到的文本
    ///   - whisper: Whisper 识别到的文本
    /// - Returns: 合并后的最终文本
    func merge(appleSpeech: String, whisper: String) async throws -> String
}
