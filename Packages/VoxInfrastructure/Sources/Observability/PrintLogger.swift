import Foundation

/// 基于 print 的日志实现
///
/// 将日志输出到控制台，用于开发调试。
public final class PrintLogger: Logger, @unchecked Sendable {

    public var minimumLevel: LogLevel

    private let subsystem: String
    private let lock = NSLock()
    private let timestampFormatter: ISO8601DateFormatter

    public init(subsystem: String = "", minimumLevel: LogLevel = .debug) {
        self.subsystem = subsystem
        self.minimumLevel = minimumLevel
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        self.timestampFormatter = formatter
    }

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        function: String,
        line: Int
    ) {
        emit(level, message: message(), context: nil, file: file, function: function, line: line)
    }

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        emit(level, message: message(), context: context, file: file, function: function, line: line)
    }

    private func emit(
        _ level: LogLevel,
        message: String,
        context: [String: Any]?,
        file: String,
        function: String,
        line: Int
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard level >= minimumLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let prefix = subsystem.isEmpty ? "" : "[\(subsystem)] "
        let timestamp = timestampFormatter.string(from: Date())
        let normalizedMessage = normalize(message)

        if let context, !context.isEmpty {
            let contextStr = context
                .map { key, value in (key, normalize(String(describing: value))) }
                .sorted { $0.0 < $1.0 }
                .map { "\($0.0)=\($0.1)" }
                .joined(separator: ", ")
            print("\(level.symbol) \(timestamp) \(prefix)\(level.name) [\(fileName):\(line)] \(function) - \(normalizedMessage) | \(contextStr)")
        } else {
            print("\(level.symbol) \(timestamp) \(prefix)\(level.name) [\(fileName):\(line)] \(function) - \(normalizedMessage)")
        }
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
