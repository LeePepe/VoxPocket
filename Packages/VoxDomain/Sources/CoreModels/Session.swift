import Foundation

/// 转录会话实体
public struct Session: Identifiable, Codable, Equatable, Sendable {
    /// 唯一标识符
    public let id: UUID
    /// 会话标题
    public var title: String
    /// 创建时间
    public let createdAt: Date
    /// 最后更新时间
    public var updatedAt: Date
    /// 当前状态
    public var state: SessionState

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        state: SessionState = .idle
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
    }
}
