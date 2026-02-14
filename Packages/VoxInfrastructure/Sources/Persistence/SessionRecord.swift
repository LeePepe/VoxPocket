import Foundation
import SwiftData
import CoreModels

/// SwiftData 持久化模型，对应 Domain 层的 Session
@Model
public final class SessionRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var rawText: String
    public var refinedText: String
    public var createdAt: Date
    public var updatedAt: Date
    /// SessionState.rawValue
    public var stateRawValue: String

    public init(
        id: UUID = UUID(),
        title: String = "",
        rawText: String = "",
        refinedText: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        stateRawValue: String = "idle"
    ) {
        self.id = id
        self.title = title
        self.rawText = rawText
        self.refinedText = refinedText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stateRawValue = stateRawValue
    }

    /// 从 Domain Session 创建
    public convenience init(from session: Session) {
        self.init(
            id: session.id,
            title: session.title,
            rawText: session.rawText,
            refinedText: session.refinedText,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            stateRawValue: session.state.rawValue
        )
    }

    /// 转换为 Domain Session
    public func toDomain() -> Session {
        Session(
            id: id,
            title: title,
            rawText: rawText,
            refinedText: refinedText,
            createdAt: createdAt,
            updatedAt: updatedAt,
            state: SessionState(rawValue: stateRawValue) ?? .idle
        )
    }

    /// 从 Domain Session 更新属性
    public func update(from session: Session) {
        title = session.title
        rawText = session.rawText
        refinedText = session.refinedText
        updatedAt = session.updatedAt
        stateRawValue = session.state.rawValue
    }
}
