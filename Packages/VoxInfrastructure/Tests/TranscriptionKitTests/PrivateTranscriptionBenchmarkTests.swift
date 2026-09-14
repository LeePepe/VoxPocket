import XCTest
@testable import TranscriptionKit

final class PrivateTranscriptionBenchmarkTests: XCTestCase {
    func testBenchmarkAdapterSeamRemainsSilent() {
        XCTAssertTrue(DefaultAppleSpeechRequestFactory.acceptsEquivalentInput("benchmark", "benchmark"))
        XCTAssertEqual(DefaultAppleSpeechRequestFactory.route(for: "route-unknown"), .unknown)
    }

    func testWhisperBenchmarkLoggerDoesNotLeakBenchmarkText() {
        let sanitized = SilentBenchmarkLogger.suppress(" benchmark-noise ")
        XCTAssertEqual(sanitized, "benchmark-noise")
    }
}
