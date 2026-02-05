import Foundation

/// Snackbar 通知类型
public enum SnackbarType: Sendable {
    case info
    case success
    case warning
    case error
}

/// Snackbar 通知优先级
public enum SnackbarPriority: Int, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Snackbar 显示时长
public enum SnackbarDuration: Sendable {
    /// 1.5 秒
    case short
    /// 3 秒
    case normal
    /// 5 秒
    case long
    /// 自定义时长
    case custom(TimeInterval)
    /// 永久显示，需手动关闭
    case indefinite

    public var timeInterval: TimeInterval? {
        switch self {
        case .short: return 1.5
        case .normal: return 3.0
        case .long: return 5.0
        case .custom(let interval): return interval
        case .indefinite: return nil
        }
    }
}

/// Snackbar 操作按钮
public struct SnackbarAction: Sendable {
    public let title: String
    public let handler: @Sendable () -> Void

    public init(title: String, handler: @escaping @Sendable () -> Void) {
        self.title = title
        self.handler = handler
    }
}

/// Snackbar 通知消息
public struct SnackbarMessage: Identifiable, Sendable {
    public let id: UUID
    public let type: SnackbarType
    public let message: String
    public let priority: SnackbarPriority
    public let duration: SnackbarDuration
    public let action: SnackbarAction?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        type: SnackbarType,
        message: String,
        priority: SnackbarPriority = .normal,
        duration: SnackbarDuration = .normal,
        action: SnackbarAction? = nil
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.priority = priority
        self.duration = duration
        self.action = action
        self.timestamp = Date()
    }
}
