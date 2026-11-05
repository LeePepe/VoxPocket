import Foundation
import Synchronization
import XCTest
import VoxCore
@testable import TranscriptionKit

final class LocalWhisperRawOutputLoggerTests: XCTestCase {
    func testNonEmptyTranscriptionReachesSessionButNeverDiagnostics() async throws {
        let sentinel = "PRIVATE_TRANSCRIPT_SENTINEL_你好世界"
        let (events, logger, telemetry) = try await transcribe(sentinel)
        XCTAssertTrue(events.contains { if case .partial(let result) = $0 { return result.text == sentinel }; return false })
        XCTAssertTrue(events.contains { if case .final(let result) = $0 { return result.text == sentinel }; return false })
        XCTAssertFalse(logger.recordedMessages.isEmpty)
        XCTAssertFalse(telemetry.recordedEvents.isEmpty)
        XCTAssertTrue(logger.assertNoCanaryLeak(canaryStrings: [sentinel, "Local Whisper raw output:"]))
        XCTAssertTrue(telemetry.assertNoCanaryLeak(canaryStrings: [sentinel]))
    }

    func testWhitespaceOutputProducesNeitherTranscriptNorRawDiagnostics() async throws {
        let (events, logger, _) = try await transcribe("   \n  ")
        XCTAssertFalse(events.contains { if case .partial = $0 { return true }; if case .final = $0 { return true }; return false })
        XCTAssertFalse(logger.recordedMessages.isEmpty)
        XCTAssertFalse(logger.recordedMessages.contains { $0.contains("Local Whisper raw output:") })
    }

    private func transcribe(_ text: String) async throws -> ([TranscriptionEvent], CanaryLogger, CanaryTelemetry) {
        let logger = CanaryLogger()
        let telemetry = CanaryTelemetry()
        let engine = PrivacySuccessEngine(text: text)
        let source = WhisperKitTranscriber(config: .init(preloadOnStart: false), logger: logger,
            recorder: MicrophoneRecorder(), telemetry: telemetry,
            permissionRequester: { true }, hasPermissionProvider: { true }, engineFactory: { _, _ in engine })
        let session = try await source.startSession(language: Locale(identifier: "zh-Hans"))
        engine.emit()
        await session.stop()
        var events: [TranscriptionEvent] = []
        for try await event in session.events() { events.append(event) }
        return (events, logger, telemetry)
    }
}

private final class PrivacySuccessEngine: LocalWhisperEngine {
    private let text: String
    private let callback = Mutex<(@Sendable (String) -> Void)?>(nil)
    init(text: String) { self.text = text }
    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws { onProgress?(1) }
    func startStreaming(languageCode: String?, onPartial: @escaping @Sendable (String) -> Void,
                        onAudioLevel: @escaping @Sendable (Float) -> Void) async throws {
        callback.withLock { $0 = onPartial }
    }
    func emit() { callback.withLock { $0 }?(text) }
    func stopStreaming() async {}
    func pauseStreaming() async {}
    func resumeStreaming() async {}
    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? { normalizedText }
    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? { normalizedText }
    private var normalizedText: String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
