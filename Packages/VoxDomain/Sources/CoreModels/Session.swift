import Foundation

/// 转录会话实体
public struct Session: Identifiable, Codable, Equatable, Sendable {
    /// 唯一标识符
    public let id: UUID
    /// 会话标题
    public var title: String
    /// 原始转录文本
    public var rawText: String
    /// 优化后的文本（LLM 处理结果）
    public var refinedText: String
    /// 创建时间
    public let createdAt: Date
    /// 最后更新时间
    public var updatedAt: Date
    /// 当前状态
    public var state: SessionState

    /// 显示用文本（优先展示 refinedText）
    public var displayText: String {
        refinedText.isEmpty ? rawText : refinedText
    }

    public init(
        id: UUID = UUID(),
        title: String = "",
        rawText: String = "",
        refinedText: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        state: SessionState = .idle
    ) {
        self.id = id
        self.title = title
        self.rawText = rawText
        self.refinedText = refinedText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
    }

    // MARK: - Codable（向后兼容）

    enum CodingKeys: String, CodingKey {
        case id, title, rawText, refinedText, createdAt, updatedAt, state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        refinedText = try container.decodeIfPresent(String.self, forKey: .refinedText) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        state = try container.decode(SessionState.self, forKey: .state)
    }
}
