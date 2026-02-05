import Foundation

/// 日志级别
public enum LogLevel: Int, Comparable, Sendable {
    /// 调试信息
    case debug = 0
    /// 性能日志
    case performance = 1
    /// 一般信息
    case info = 2
    /// 警告
    case warning = 3
    /// 错误
    case error = 4
    /// 严重错误
    case critical = 5

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 显示符号
    public var symbol: String {
        switch self {
        case .debug: return "🔍"
        case .performance: return "⏱️"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔥"
        }
    }

    /// 显示名称
    public var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .performance: return "PERF"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
}
