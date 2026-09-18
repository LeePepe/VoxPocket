import Foundation
import XCTest
@testable import TranscriptionKit

final class RealtimeConfigurationTests: XCTestCase {
    func testDedicatedTranscriptionURLAndHeaderKeepSecretsOutOfURLAndDescription() throws {
        let config = try AzureRealtimeTranscriptionConfig(endpoint: URL(string: "https://example.invalid")!,
            apiKey: "synthetic-secret", deployment: "speech-live")
        let request = try config.request()
        XCTAssertEqual(request.url?.absoluteString, "wss://example.invalid/openai/v1/realtime?intent=transcription")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "synthetic-secret")
        XCTAssertFalse(config.description.contains("synthetic-secret"))
        XCTAssertFalse(config.description.contains("example.invalid"))
    }

    func testRejectsUnsafeEndpointAndDeploymentWithoutEchoingInput() {
        for raw in ["http://example.invalid", "https://user:pass@example.invalid", "https://example.invalid/a",
                    "https://example.invalid?token=secret", "https://example.invalid#secret"] {
            XCTAssertThrowsError(try AzureRealtimeTranscriptionConfig(endpoint: URL(string: raw)!,
                apiKey: "key", deployment: "live")) { error in
                XCTAssertEqual(error as? RealtimeTranscriptionError, .invalidConfiguration)
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
        for name in ["", "../live", "live\n", "a/b"] {
            XCTAssertThrowsError(try AzureRealtimeTranscriptionConfig(endpoint: URL(string: "https://example.invalid")!,
                apiKey: "key", deployment: name))
        }
    }
}
