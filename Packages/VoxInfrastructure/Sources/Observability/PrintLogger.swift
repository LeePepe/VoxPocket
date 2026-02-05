import Foundation

/// 基于 print 的日志实现
///
/// 将日志输出到控制台，用于开发调试。
public final class PrintLogger: Logger, @unchecked Sendable {

    public var minimumLevel: LogLevel

    private let subsystem: String
    private let lock = NSLock()
    private let timestampFormatter = ISO8601DateFormatter()

    public init(subsystem: String = "", minimumLevel: LogLevel = .debug) {
        self.subsystem = subsystem
        self.minimumLevel = minimumLevel
    }

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        function: String,
        line: Int
    ) {
        lock.lock()
        let minLevel = minimumLevel
        lock.unlock()

        guard level >= minLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let prefix = subsystem.isEmpty ? "" : "[\(subsystem)] "
        let timestamp = timestampFormatter.string(from: Date())
        print("\(level.symbol) \(timestamp) \(prefix)\(level.name) [\(fileName):\(line)] \(function) — \(message())")
    }

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        lock.lock()
        let minLevel = minimumLevel
        lock.unlock()

        guard level >= minLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let prefix = subsystem.isEmpty ? "" : "[\(subsystem)] "
        let contextStr = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let timestamp = timestampFormatter.string(from: Date())
        print("\(level.symbol) \(timestamp) \(prefix)\(level.name) [\(fileName):\(line)] \(function) — \(message()) | \(contextStr)")
    }
}
