import Foundation

/// 文本补丁（变更单元）
///
/// 表示对文本的一次原子性修改，包含足够的信息以支持撤销操作。
public struct Patch: Identifiable, Codable, Equatable, Sendable {
    /// 唯一标识符
    public let id: UUID
    /// 创建时间戳
    public let timestamp: Date
    /// 变更来源
    public let source: ChangeSource
    /// 被替换的文本范围
    public let range: TextRange
    /// 被替换的原始文本
    public let oldText: String
    /// 替换后的新文本
    public let newText: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: ChangeSource,
        range: TextRange,
        oldText: String,
        newText: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.range = range
        self.oldText = oldText
        self.newText = newText
    }

    /// 是否为插入操作
    public var isInsertion: Bool {
        oldText.isEmpty && !newText.isEmpty
    }

    /// 是否为删除操作
    public var isDeletion: Bool {
        !oldText.isEmpty && newText.isEmpty
    }

    /// 是否为替换操作
    public var isReplacement: Bool {
        !oldText.isEmpty && !newText.isEmpty
    }

    /// 长度变化量（正数表示增加，负数表示减少）
    public var lengthDelta: Int {
        newText.utf16.count - oldText.utf16.count
    }
}
