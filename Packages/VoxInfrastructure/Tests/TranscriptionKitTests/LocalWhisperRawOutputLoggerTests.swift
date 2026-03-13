import XCTest
import Observability
@testable import TranscriptionKit

final class LocalWhisperRawOutputLoggerTests: XCTestCase {
    func testLogsDebugMessageForNonEmptyRawOutput() {
        let logger = SpyLogger()

        LocalWhisperRawOutputLogger.log("<|zh|> 你好，世界", logger: logger)

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries.first?.level, .debug)
        XCTAssertEqual(logger.entries.first?.message, "Local Whisper raw output: <|zh|> 你好，世界")
    }

    func testSkipsLoggingForWhitespaceOnlyRawOutput() {
        let logger = SpyLogger()

        LocalWhisperRawOutputLogger.log("   \n  ", logger: logger)

        XCTAssertTrue(logger.entries.isEmpty)
    }
}

private final class SpyLogger: Logger, @unchecked Sendable {
    struct Entry: Equatable {
        let level: LogLevel
        let message: String
    }

    var minimumLevel: LogLevel = .debug
    private(set) var entries: [Entry] = []

    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        function: String,
        line: Int
    ) {
        entries.append(Entry(level: level, message: message()))
    }

    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        entries.append(Entry(level: level, message: message()))
    }
}
