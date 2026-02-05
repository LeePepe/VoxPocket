import Foundation
import TranscriptionKit

/// 转录元数据（轻量级，从 TranscriptionResult 提取）
public struct TranscriptionMetadata: Sendable, Equatable {
    public let type: TranscriptionResultType
    public let confidence: Double?
    public let locale: Locale?

    public init(type: TranscriptionResultType, confidence: Double?, locale: Locale?) {
        self.type = type
        self.confidence = confidence
        self.locale = locale
    }

    /// 从 TranscriptionResult 创建
    public init(from result: TranscriptionResult) {
        self.type = result.type
        self.confidence = result.confidence
        self.locale = result.locale
    }
}
