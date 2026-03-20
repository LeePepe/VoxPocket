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

// MARK: - MultiRecognizerTranscriber

/// 多识别器转录器协议
///
/// 所有同时运行多路识别器的 Transcriber（如 HybridWhisperTranscriber、
/// HybridLocalWhisperTranscriber）均遵循此协议，支持注入 LLM 合并器。
public protocol MultiRecognizerTranscriber: TranscriptionCoordinator {
    /// 可选的 LLM 合并器；nil 时直接使用 Whisper 结果
    var merger: (any TranscriptionMerger)? { get set }
}

// MARK: - Shared helper

/// 尝试用 LLM 合并双路识别结果，失败或条件不满足时回退到 whisperText
///
/// 供所有遵循 `MultiRecognizerTranscriber` 的类在 `stop()` 中调用，
/// 避免每个类重复实现相同的 try/catch + fallback 逻辑。
public func mergedTranscription(
    appleSpeech: String,
    whisper: String,
    merger: (any TranscriptionMerger)?
) async -> String {
    guard let merger, !appleSpeech.isEmpty, appleSpeech != whisper else {
        return whisper
    }
    return (try? await merger.merge(appleSpeech: appleSpeech, whisper: whisper)) ?? whisper
}
