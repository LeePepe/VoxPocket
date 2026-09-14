import Foundation
import LokiKit

/// Production-side benchmark seam: benchmark logs are intentionally silent in
/// synthetic/test runs and when a benchmark logger is injected into the adapter.
public final class SilentBenchmarkLogger: Logger, @unchecked Sendable {
    public var minimumLevel: LogLevel = .critical

    public init() {}

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        function: String,
        line: Int
    ) {
        _ = level
        _ = message()
        _ = file
        _ = function
        _ = line
    }

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        _ = level
        _ = message()
        _ = context
        _ = file
        _ = function
        _ = line
    }

    static func log(_ message: String, logger: Logger? = nil) {
        _ = message
        _ = logger
    }

    static func suppress(_ rawText: String) -> String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
