import Foundation

/// 检查点（全文快照）
///
/// 用于优化历史重建性能，避免从头应用所有补丁。
public struct Checkpoint: Identifiable, Codable, Equatable, Sendable {
    /// 唯一标识符
    public let id: UUID
    /// 创建时间戳
    public let timestamp: Date
    /// 完整文本内容
    public let fullText: String
    /// 对应的补丁索引（此检查点之前的补丁数量）
    public let patchIndex: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        fullText: String,
        patchIndex: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fullText = fullText
        self.patchIndex = patchIndex
    }
}
