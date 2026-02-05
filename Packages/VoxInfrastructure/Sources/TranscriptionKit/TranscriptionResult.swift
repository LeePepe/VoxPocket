import Foundation

/// 转录结果类型
public enum TranscriptionResultType: String, Sendable {
    /// 临时结果（可能随后续语音输入而变化）
    case partial
    /// 最终结果（稳定，不会再变化）
    case final
}

/// 转录结果
public struct TranscriptionResult: Sendable, Equatable {
    /// 转录的文本内容
    public let text: String
    /// 结果类型（临时/最终）
    public let type: TranscriptionResultType
    /// 置信度（0.0 - 1.0），可能不可用
    public let confidence: Double?
    /// 时间戳
    public let timestamp: Date
    /// 语言标识
    public let locale: Locale?

    public init(
        text: String,
        type: TranscriptionResultType,
        confidence: Double? = nil,
        timestamp: Date = Date(),
        locale: Locale? = nil
    ) {
        self.text = text
        self.type = type
        self.confidence = confidence
        self.timestamp = timestamp
        self.locale = locale
    }

    /// 是否为最终结果
    public var isFinal: Bool {
        type == .final
    }
}
