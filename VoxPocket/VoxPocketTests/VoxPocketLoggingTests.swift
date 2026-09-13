import XCTest
@testable import VoxPocket

@MainActor
final class VoxPocketLoggingTests: XCTestCase {
    private func withPreferences(_ body: (UserDefaults, String) -> Void) {
        let suite = "VoxPocketLoggingTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        body(preferences, suite)
    }

    func testPersistentLocalOptInUsesLoopbackOnMacOnly() {
        withPreferences { preferences, suite in
            preferences.set(true, forKey: VoxPocketLogging.localLoggingEnabledKey)
            preferences.synchronize()
            let reloaded = UserDefaults(suiteName: suite)!
            let endpoint = VoxPocketLogging.endpoint(environment: [:], defaults: reloaded)
            #if os(macOS)
            XCTAssertEqual(endpoint?.absoluteString, "http://localhost:3100/loki/api/v1/push")
            #else
            XCTAssertNil(endpoint)
            #endif
        }
    }

    func testPersistentOptOutDisablesAutomaticLocalUpload() {
        withPreferences { preferences, _ in
            preferences.set(false, forKey: VoxPocketLogging.localLoggingEnabledKey)
            XCTAssertNil(VoxPocketLogging.endpoint(environment: [:], defaults: preferences))
        }
    }

    func testInvalidPersistentChoiceFailsClosed() {
        withPreferences { preferences, _ in
            for choice in ["yes", 1, [true]] as [Any] {
                preferences.set(choice, forKey: VoxPocketLogging.localLoggingEnabledKey)
                XCTAssertNil(VoxPocketLogging.endpoint(environment: [:], defaults: preferences))
            }
        }
    }

    func testAbsentPreferencePreservesBuildDefault() {
        withPreferences { preferences, _ in
            let endpoint = VoxPocketLogging.endpoint(environment: [:], defaults: preferences)
            #if DEBUG && os(macOS)
            XCTAssertEqual(endpoint?.host, "localhost")
            #else
            XCTAssertNil(endpoint)
            #endif
        }
    }

    func testExplicitEndpointTakesPrecedenceOverPersistentChoice() {
        withPreferences { preferences, _ in
            preferences.set(false, forKey: VoxPocketLogging.localLoggingEnabledKey)
            XCTAssertEqual(VoxPocketLogging.endpoint(
                environment: ["LOKI_ENDPOINT": "http://127.0.0.1:3100/loki/api/v1/push"],
                defaults: preferences
            )?.host, "127.0.0.1")
            preferences.set(true, forKey: VoxPocketLogging.localLoggingEnabledKey)
            XCTAssertNil(VoxPocketLogging.endpoint(environment: ["LOKI_ENDPOINT": ""], defaults: preferences))
        }
    }

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
