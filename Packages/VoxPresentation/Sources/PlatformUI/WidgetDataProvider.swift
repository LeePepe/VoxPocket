import Foundation
import CoreModels

#if os(iOS)

/// Widget 数据提供者协议 (iOS)
///
/// 为 iOS Widget 提供数据接口。
public protocol WidgetDataProvider: Sendable {

    /// 获取最近的会话
    ///
    /// - Parameter limit: 最大数量
    /// - Returns: 会话数组
    func recentSessions(limit: Int) async -> [Session]

    /// 快速录音入口 URL Scheme
    var quickRecordURL: URL { get }

    /// 新建会话 URL Scheme
    var newSessionURL: URL { get }

    /// 打开指定会话的 URL
    ///
    /// - Parameter sessionId: 会话 ID
    /// - Returns: URL
    func openSessionURL(sessionId: UUID) -> URL
}

/// Widget 时间线条目
public struct VoxWidgetEntry: Sendable {
    /// 日期
    public let date: Date
    /// 最近会话
    public let recentSessions: [Session]
    /// 是否有活跃会话
    public let hasActiveSession: Bool

    public init(
        date: Date,
        recentSessions: [Session],
        hasActiveSession: Bool
    ) {
        self.date = date
        self.recentSessions = recentSessions
        self.hasActiveSession = hasActiveSession
    }
}

#endif
