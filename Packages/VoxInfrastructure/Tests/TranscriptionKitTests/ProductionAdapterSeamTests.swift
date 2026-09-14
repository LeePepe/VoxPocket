import Synchronization
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

private final class SpyLogger: Logger {
    struct Entry: Equatable {
        let level: LogLevel
        let message: String
    }

    private let state = Mutex(State())

    var minimumLevel: LogLevel {
        get { state.withLock { $0.minimumLevel } }
        set { state.withLock { $0.minimumLevel = newValue } }
    }

    var entries: [Entry] {
        state.withLock { $0.entries }
    }

    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        function: String,
        line: Int
    ) {
        state.withLock { $0.entries.append(Entry(level: level, message: message())) }
    }

    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        state.withLock { $0.entries.append(Entry(level: level, message: message())) }
    }

    private struct State {
        var minimumLevel: LogLevel = .debug
        var entries: [Entry] = []
    }
}
