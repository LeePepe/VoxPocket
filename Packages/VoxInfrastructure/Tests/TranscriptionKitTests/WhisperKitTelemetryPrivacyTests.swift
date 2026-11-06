import Foundation
import VoxCore
import XCTest
@testable import TranscriptionKit

final class WhisperKitTelemetryPrivacyTests: XCTestCase {
    func testModelLoadFailureEmitsOnlyClosedTelemetryAndDiagnostics() async {
        let telemetry = CanaryTelemetry()
        let logger = CanaryLogger()
        let sut = makeTranscriber(engine: PrivacyFailureEngine(prepareFails: true), telemetry: telemetry, logger: logger)
        do { try await sut.start(language: Locale(identifier: "zh-Hans")); XCTFail("Expected preparation failure") }
        catch { }
        XCTAssertEqual(telemetry.recordedEvents, [
            VoxTelemetryEvent(name: "whisper.model.load_failed", fields: [
                .label("model", .source("whisperKit")), .label("error_kind", .reason("model_preparation"))]),
            VoxTelemetryEvent(name: "transcription.failed", fields: [
                .label("provider", .provider("whisperkit")), .label("model", .source("whisperKit")),
                .label("phase", .step("model_load")), .label("error_kind", .reason("model_preparation"))])
        ])
        XCTAssertEqual(sut.modelLoadingState, .failed("Model preparation failed"))
        XCTAssertTrue(telemetry.assertNoCanaryLeak(canaryStrings: PrivacySentinel.values))
        XCTAssertTrue(logger.assertNoCanaryLeak(canaryStrings: PrivacySentinel.values))
    }

    func testStreamStartFailureEmitsOnlyClosedTelemetryAndDiagnostics() async {
        let telemetry = CanaryTelemetry()
        let logger = CanaryLogger()
        let sut = makeTranscriber(engine: PrivacyFailureEngine(prepareFails: false), telemetry: telemetry, logger: logger)
        do { try await sut.start(language: Locale(identifier: "zh-Hans")); XCTFail("Expected stream failure") }
        catch { }
        let load = telemetry.recordedEvents.first?.fields.first { String(describing: $0.key) == "load_ms" }
        XCTAssertNotNil(load)
        guard let load else { return }
        XCTAssertEqual(telemetry.recordedEvents, [
            VoxTelemetryEvent(name: "whisper.model.loaded", fields: [.label("model", .source("whisperKit")), load]),
            VoxTelemetryEvent(name: "transcription.failed", fields: [
                .label("provider", .provider("whisperkit")), .label("model", .source("whisperKit")),
                .label("phase", .step("stream_start")), .label("error_kind", .reason("streaming_start"))])
        ])
        XCTAssertTrue(telemetry.assertNoCanaryLeak(canaryStrings: PrivacySentinel.values))
        XCTAssertTrue(logger.assertNoCanaryLeak(canaryStrings: PrivacySentinel.values))
    }

    private func makeTranscriber(engine: any LocalWhisperEngine, telemetry: CanaryTelemetry, logger: CanaryLogger) -> WhisperKitTranscriber {
        WhisperKitTranscriber(config: .init(model: "synthetic-model", preloadOnStart: false), logger: logger,
            recorder: MicrophoneRecorder(logger: logger, storageLocations: testStorageLocations), telemetry: telemetry,
            permissionRequester: { true }, hasPermissionProvider: { true }, engineFactory: { _, _ in engine }, autoPreload: false)
    }
}

private enum PrivacySentinel {
    static let values = ["audio=AUDIO_SENTINEL", "transcript=TRANSCRIPT_SENTINEL", "error=ERROR_SENTINEL",
        "endpoint=https://example.invalid/ENDPOINT_SENTINEL", "sas=SAS_SENTINEL", "credential=CREDENTIAL_SENTINEL"]
}
private struct PrivacyFailure: Error, LocalizedError {
    var errorDescription: String? { PrivacySentinel.values.joined(separator: "|") }
}
private struct PrivacyFailureEngine: LocalWhisperEngine {
    let prepareFails: Bool
    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        if prepareFails { throw PrivacyFailure() }
    }
    func startStreaming(languageCode: String?, onPartial: @escaping @Sendable (String) -> Void,
                        onAudioLevel: @escaping @Sendable (Float) -> Void) async throws { throw PrivacyFailure() }
    func stopStreaming() async {}
    func pauseStreaming() async {}
    func resumeStreaming() async {}
    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? { nil }
    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? { nil }
}
