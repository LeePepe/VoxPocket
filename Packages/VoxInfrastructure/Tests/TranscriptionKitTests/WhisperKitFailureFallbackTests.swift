import Foundation
import Observability
import XCTest
@testable import TranscriptionKit

final class WhisperKitFailureFallbackTests: XCTestCase {
    func testModelLoadFailureStopsTranscriber() async {
        let sut = WhisperKitTranscriber(
            config: .failingForTest,
            logger: PrintLogger(subsystem: "WhisperKitFailureFallbackTests"),
            recorder: MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitFailureFallbackTests.Mic")),
            telemetry: NoopTelemetryService(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in FailingLocalWhisperEngine() },
            autoPreload: true
        )

        await XCTAssertThrowsErrorAsync {
            try await sut.start(language: Locale(identifier: "zh-Hans"))
        }
        XCTAssertFalse(sut.isTranscribing)
    }
}

private final class FailingLocalWhisperEngine: LocalWhisperEngine {
    func prepare() async throws {
        throw NSError(domain: "WhisperKitFailureFallbackTests", code: 1001)
    }

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        _ = languageCode
        _ = onPartial
        _ = onAudioLevel
        throw NSError(domain: "WhisperKitFailureFallbackTests", code: 1002)
    }

    func stopStreaming() async {}
    func pauseStreaming() async {}
    func resumeStreaming() async {}
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // expected
    }
}
