import Foundation

/// 日志服务协议
///
/// 提供统一的日志记录接口。
public protocol Logger: AnyObject, Sendable {

    /// 最小日志级别（低于此级别的日志将被忽略）
    var minimumLevel: LogLevel { get set }

    /// 记录日志
    ///
    /// - Parameters:
    ///   - level: 日志级别
    ///   - message: 日志消息（延迟求值）
    ///   - file: 源文件路径
    ///   - function: 函数名
    ///   - line: 行号
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        function: String,
        line: Int
    )

    /// 记录日志（带上下文）
    ///
    /// - Parameters:
    ///   - level: 日志级别
    ///   - message: 日志消息
    ///   - context: 附加上下文信息
    ///   - file: 源文件路径
    ///   - function: 函数名
    ///   - line: 行号
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    )
}

// MARK: - 便捷方法扩展

public extension Logger {

    /// 记录日志（自动填充调用位置信息）
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level, message(), file: file, function: function, line: line)
    }

    /// 记录日志（带上下文，自动填充调用位置信息）
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level, message(), context: context, file: file, function: function, line: line)
    }

    /// 记录调试日志
    func debug(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.debug, message(), file: file, function: function, line: line)
    }

    /// 记录调试日志（带上下文）
    func debug(
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.debug, message(), context: context, file: file, function: function, line: line)
    }

    /// 记录信息日志
    func info(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, message(), file: file, function: function, line: line)
    }

    /// 记录信息日志（带上下文）
    func info(
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, message(), context: context, file: file, function: function, line: line)
    }

    /// 记录警告日志
    func warning(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.warning, message(), file: file, function: function, line: line)
    }

    /// 记录警告日志（带上下文）
    func warning(
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.warning, message(), context: context, file: file, function: function, line: line)
    }

    /// 记录错误日志
    func error(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, message(), file: file, function: function, line: line)
    }

    /// 记录错误日志（带上下文）
    func error(
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, message(), context: context, file: file, function: function, line: line)
    }

    /// 记录严重错误日志
    func critical(
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.critical, message(), file: file, function: function, line: line)
    }

    /// 记录严重错误日志（带上下文）
    func critical(
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.critical, message(), context: context, file: file, function: function, line: line)
    }

    /// 记录错误对象
    func error(
        _ error: Error,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, error.localizedDescription, file: file, function: function, line: line)
    }

    /// 记录性能日志（同步）
    @discardableResult
    func performance<T>(
        _ name: @autoclosure () -> String,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ operation: () throws -> T
    ) rethrows -> T {
        let startTime = performanceStart()
        do {
            let result = try operation()
            performanceEnd(name(), start: startTime, context: context, file: file, function: function, line: line)
            return result
        } catch {
            performanceEnd(name(), start: startTime, context: context, error: error, file: file, function: function, line: line)
            throw error
        }
    }

    /// 记录性能日志（异步）
    @discardableResult
    func performance<T>(
        _ name: @autoclosure () -> String,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let startTime = performanceStart()
        do {
            let result = try await operation()
            performanceEnd(name(), start: startTime, context: context, file: file, function: function, line: line)
            return result
        } catch {
            performanceEnd(name(), start: startTime, context: context, error: error, file: file, function: function, line: line)
            throw error
        }
    }

    /// 性能计时起点（适用于 actor 场景）
    func performanceStart() -> ContinuousClock.Instant {
        ContinuousClock().now
    }

    /// 记录性能日志（成功）
    func performanceEnd(
        _ name: @autoclosure () -> String,
        start: ContinuousClock.Instant,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let milliseconds = Self.milliseconds(from: ContinuousClock().now - start)
        var merged = context
        merged["duration_ms"] = String(format: "%.2f", milliseconds)
        log(.performance, "\(name())耗时", context: merged, file: file, function: function, line: line)
    }

    /// 记录性能日志（失败）
    func performanceEnd(
        _ name: @autoclosure () -> String,
        start: ContinuousClock.Instant,
        context: [String: Any] = [:],
        error: Error,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let milliseconds = Self.milliseconds(from: ContinuousClock().now - start)
        var merged = context
        merged["duration_ms"] = String(format: "%.2f", milliseconds)
        merged["error"] = error.localizedDescription
        log(.error, "\(name())失败", context: merged, file: file, function: function, line: line)
    }
}

private extension Logger {
    static func milliseconds(from duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
