import Foundation

/// LLM 优化请求
public struct RefinementRequest: Sendable {
    /// 要优化的文本
    public let text: String
    /// 自定义提示词（可选）
    public let customPrompt: String?
    /// 附加选项
    public let options: [String: String]
    /// 转录元数据（可选，用于提供上下文）
    public let transcriptionMetadata: TranscriptionMetadata?

    public init(
        text: String,
        customPrompt: String? = nil,
        options: [String: String] = [:],
        transcriptionMetadata: TranscriptionMetadata? = nil
    ) {
        self.text = text
        self.customPrompt = customPrompt
        self.options = options
        self.transcriptionMetadata = transcriptionMetadata
    }
}
