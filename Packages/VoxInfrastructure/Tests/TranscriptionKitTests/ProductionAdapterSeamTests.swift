import XCTest
import LokiKit
@testable import TranscriptionKit

final class ProductionAdapterSeamTests: XCTestCase {
    func testRequestFactorySharesPolicyAcrossAdapterSeams() {
        let bufferRequest = DefaultAppleSpeechRequestFactory.makeRequest(for: .audioBuffer)
        let fileRequest = DefaultAppleSpeechRequestFactory.makeRequest(for: .fileURL)

        XCTAssertTrue(bufferRequest.shouldReportPartialResults)
        XCTAssertTrue(fileRequest.shouldReportPartialResults)
        XCTAssertFalse(bufferRequest.requiresOnDeviceRecognition)
        XCTAssertFalse(fileRequest.requiresOnDeviceRecognition)
    }

    func testUnknownRouteIsRecordedWhenRouteCannotBeProven() {
        XCTAssertEqual(DefaultAppleSpeechRequestFactory.route(for: "unknown-route"), .unknown)
        XCTAssertEqual(DefaultAppleSpeechRequestFactory.route(for: nil), .unknown)
    }

    func testEquivalentFileAndBufferInputsAreAcceptedAsSameContent() {
        XCTAssertTrue(DefaultAppleSpeechRequestFactory.acceptsEquivalentInput("alpha", "alpha"))
        XCTAssertTrue(DefaultAppleSpeechRequestFactory.acceptsEquivalentInput("  alpha  ", "alpha"))
        XCTAssertFalse(DefaultAppleSpeechRequestFactory.acceptsEquivalentInput("alpha", "beta"))
    }

    func testSilentBenchmarkLoggerSupressesRawBenchmarkNoise() {
        let logger = SpyLogger()
        SilentBenchmarkLogger.log("benchmark: should-not-log", logger: logger)
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
