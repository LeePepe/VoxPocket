import Foundation
import Observability
import XCTest
@testable import TranscriptionKit

final class WhisperKitTranscriberBehaviorTests: XCTestCase {
    func testProviderTypeIsWhisper() {
        let sut = WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: PrintLogger(subsystem: "WhisperKitTranscriberTests"),
            recorder: MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitTranscriberTests.Mic")),
            telemetry: NoopTelemetryService(),
            engineFactory: { _, _ in FakeLocalWhisperEngine() }
        )
        XCTAssertEqual(sut.speechRecognitionService.providerType, .whisper)
    }

    func testStartThenStopChangesState() async throws {
        let sut = WhisperKitTranscriber(
            config: .default,
            logger: PrintLogger(subsystem: "WhisperKitTranscriberTests"),
            recorder: MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitTranscriberTests.Mic")),
            telemetry: NoopTelemetryService(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in FakeLocalWhisperEngine() },
            autoPreload: true
        )

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(sut.isTranscribing)

        await sut.stop()
        XCTAssertFalse(sut.isTranscribing)
    }
}

private final class FakeLocalWhisperEngine: LocalWhisperEngine {
    func prepare() async throws {}

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        _ = languageCode
        onAudioLevel(0.2)
    }

    func stopStreaming() async {}
    func pauseStreaming() async {}
    func resumeStreaming() async {}
}
