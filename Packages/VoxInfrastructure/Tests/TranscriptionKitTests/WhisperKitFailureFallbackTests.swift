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

    func testSecondStartRetriesAfterInitialPreloadFailure() async throws {
        let factory = FailOnceEngineFactory()
        let sut = WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: PrintLogger(subsystem: "WhisperKitFailureFallbackTests"),
            recorder: MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitFailureFallbackTests.Mic")),
            telemetry: NoopTelemetryService(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in factory.make() },
            autoPreload: false
        )

        await XCTAssertThrowsErrorAsync {
            try await sut.start(language: Locale(identifier: "zh-Hans"))
        }
        XCTAssertFalse(sut.isTranscribing)

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(sut.isTranscribing)
        await sut.stop()
        XCTAssertFalse(sut.isTranscribing)
    }
}

private final class FailingLocalWhisperEngine: LocalWhisperEngine {
    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        _ = onProgress
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
    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? { nil }
    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? { nil }
}

private final class FailOnceEngineFactory: @unchecked Sendable {
    let state = FailOnceState()

    func make() -> any LocalWhisperEngine {
        FailOnceLocalWhisperEngine(state: state)
    }
}

private actor FailOnceState {
    private var prepareAttempts = 0

    func nextPrepareAttempt() -> Int {
        prepareAttempts += 1
        return prepareAttempts
    }
}

private final class FailOnceLocalWhisperEngine: LocalWhisperEngine {
    private let state: FailOnceState

    init(state: FailOnceState) {
        self.state = state
    }

    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        let attempt = await state.nextPrepareAttempt()
        if attempt == 1 {
            throw NSError(domain: "WhisperKitFailureFallbackTests", code: 1003)
        }
        onProgress?(1.0)
    }

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        _ = languageCode
        _ = onPartial
        onAudioLevel(0.1)
    }

    func stopStreaming() async {}
    func pauseStreaming() async {}
    func resumeStreaming() async {}
    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? { nil }
    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? { nil }
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
