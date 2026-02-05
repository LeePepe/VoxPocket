import Foundation

/// 文本范围（位置 + 长度）
public struct TextRange: Codable, Equatable, Sendable, Hashable {
    /// 起始位置（基于 UTF-16 偏移）
    public let location: Int
    /// 长度
    public let length: Int

    public init(location: Int, length: Int) {
        precondition(location >= 0, "Location must be non-negative")
        precondition(length >= 0, "Length must be non-negative")
        self.location = location
        self.length = length
    }

    /// 结束位置（不包含）
    public var end: Int {
        location + length
    }

    /// 是否为空范围
    public var isEmpty: Bool {
        length == 0
    }

    /// 从 NSRange 创建
    public init(_ nsRange: NSRange) {
        self.location = nsRange.location
        self.length = nsRange.length
    }

    /// 转换为 NSRange
    public var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}
