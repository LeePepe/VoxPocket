import XCTest
@testable import VoxPocket

@MainActor
final class VoxPocketLoggingTests: XCTestCase {
    func testExplicitEndpointIsUsed() {
        XCTAssertEqual(
            VoxPocketLogging.endpoint(environment: ["LOKI_ENDPOINT": "http://127.0.0.1:3100/loki/api/v1/push"])?.host,
            "127.0.0.1"
        )
    }

    func testInvalidExplicitEndpointDoesNotFallBackToLocalhost() {
        for raw in ["", "not-a-url", "file:///tmp/log", "https://user:password@example.com/log"] {
            XCTAssertNil(VoxPocketLogging.endpoint(environment: ["LOKI_ENDPOINT": raw]))
        }
    }

    func testPolicyDoesNotApproveSensitiveContentFields() {
        for key in ["text", "transcript", "prompt", "response", "error", "token", "api_key"] {
            XCTAssertFalse(VoxPocketLogging.allowedContextKeys.contains(key))
        }
        XCTAssertFalse(VoxPocketLogging.allowedMessages.contains("Local Whisper raw output: private text"))
        XCTAssertFalse(VoxPocketLogging.allowedMessages.contains("Recording started: private text"))
        XCTAssertTrue(VoxPocketLogging.allowedMessages.contains("Recording started"))
    }
}
