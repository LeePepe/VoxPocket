import Foundation
import LokiKit
import Synchronization
import XCTest
@testable import TranscriptionKit

final class WhisperKitTelemetryPrivacyTests: XCTestCase {
    func testModelLoadFailureEmitsOnlyClosedTelemetryAndDiagnostics() async {
        let sentinel = PrivacySentinel.payload
        let telemetry = RecordingTelemetryService()
        let logger = RecordingLogger()
        let sut = makeTranscriber(
            engine: PrivacyFailureEngine(prepareError: PrivacySentinelError(payload: sentinel)),
            telemetry: telemetry,
            logger: logger
        )

        await XCTAssertThrowsErrorAsync {
            try await sut.start(language: Locale(identifier: "zh-Hans"))
        }

        XCTAssertEqual(
            telemetry.recordedEvents,
            [
                RecordedEvent(
                    name: VoxPocketTelemetryEventName.whisperModelLoadFailed.rawValue,
                    properties: [
                        "model": "synthetic-model",
                        "category": "model_preparation"
                    ]
                ),
                RecordedEvent(
                    name: VoxPocketTelemetryEventName.transcriptionFailed.rawValue,
                    properties: [
                        "provider": "whisperkit",
                        "model": "synthetic-model",
                        "phase": "model_load",
                        "category": "model_preparation"
                    ]
                )
            ]
        )
        assertSentinelsAbsent(PrivacySentinel.values, telemetry: telemetry, logger: logger)
        XCTAssertEqual(sut.modelLoadingState, .failed(sentinel))
    }

    func testStreamStartFailureEmitsOnlyClosedTelemetryAndDiagnostics() async {
        let sentinel = PrivacySentinel.payload
        let telemetry = RecordingTelemetryService()
        let logger = RecordingLogger()
        let sut = makeTranscriber(
            engine: PrivacyFailureEngine(streamError: PrivacySentinelError(payload: sentinel)),
            telemetry: telemetry,
            logger: logger
        )

        await XCTAssertThrowsErrorAsync {
            try await sut.start(language: Locale(identifier: "zh-Hans"))
        }

        let loadMilliseconds = telemetry.recordedEvents.first?.properties["load_ms"]
        XCTAssertNotNil(loadMilliseconds.flatMap(Int.init))
        XCTAssertEqual(
            telemetry.recordedEvents,
            [
                RecordedEvent(
                    name: VoxPocketTelemetryEventName.whisperModelLoaded.rawValue,
                    properties: [
                        "model": "synthetic-model",
                        "load_ms": loadMilliseconds ?? ""
                    ]
                ),
                RecordedEvent(
                    name: VoxPocketTelemetryEventName.transcriptionFailed.rawValue,
                    properties: [
                        "provider": "whisperkit",
                        "model": "synthetic-model",
                        "phase": "stream_start",
                        "category": "streaming_start"
                    ]
                )
            ]
        )
        assertSentinelsAbsent(PrivacySentinel.values, telemetry: telemetry, logger: logger)
    }

    private func makeTranscriber(
        engine: any LocalWhisperEngine,
        telemetry: RecordingTelemetryService,
        logger: RecordingLogger
    ) -> WhisperKitTranscriber {
        WhisperKitTranscriber(
            config: LocalWhisperKitConfig(model: "synthetic-model", preloadOnStart: false),
            logger: logger,
            recorder: MicrophoneRecorder(logger: logger),
            telemetry: telemetry,
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in engine },
            autoPreload: false
        )
    }

    private func assertSentinelsAbsent(
        _ sentinels: [String],
        telemetry: RecordingTelemetryService,
        logger: RecordingLogger,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let telemetryOutput = telemetry.recordedEvents
            .flatMap { [$0.name] + $0.properties.flatMap { [$0.key, $0.value] } }
            .joined(separator: " ")
        let diagnosticOutput = logger.recordedMessages.joined(separator: " ")
        for sentinel in sentinels {
            XCTAssertFalse(telemetryOutput.contains(sentinel), file: file, line: line)
            XCTAssertFalse(diagnosticOutput.contains(sentinel), file: file, line: line)
        }
    }
}

private enum PrivacySentinel {
    static let values = [
        "audio=AUDIO_SENTINEL",
        "transcript=TRANSCRIPT_SENTINEL",
        "error=ERROR_SENTINEL",
        "endpoint=https://example.invalid/ENDPOINT_SENTINEL",
        "sas=SAS_SENTINEL",
        "credential=CREDENTIAL_SENTINEL"
    ]
    static let payload = values.joined(separator: "|")
}

private struct PrivacySentinelError: LocalizedError, CustomStringConvertible, Sendable {
    let payload: String

    var errorDescription: String? { payload }
    var description: String { payload }
}

private struct RecordedEvent: Equatable {
    let name: String
    let properties: [String: String]
}

private final class RecordingTelemetryService: TelemetryService, Sendable {
    private struct State {
        var isEnabled = true
        var events: [RecordedEvent] = []
    }

    private let state = Mutex(State())

    var isEnabled: Bool {
        get { state.withLock { $0.isEnabled } }
        set { state.withLock { $0.isEnabled = newValue } }
    }

    var recordedEvents: [RecordedEvent] {
        state.withLock { $0.events }
    }

    func track(_ event: TelemetryEvent) {
        track(name: event.name, properties: event.properties)
    }

    func track(name: String, properties: [String: String]) {
        state.withLock { $0.events.append(RecordedEvent(name: name, properties: properties)) }
    }

    func flush() async {}
    func resetIdentifier() {}
}

private final class RecordingLogger: Logger, Sendable {
    private struct State {
        var minimumLevel: LogLevel = .debug
        var messages: [String] = []
    }

    private let state = Mutex(State())

    var minimumLevel: LogLevel {
        get { state.withLock { $0.minimumLevel } }
        set { state.withLock { $0.minimumLevel = newValue } }
    }

    var recordedMessages: [String] {
        state.withLock { $0.messages }
    }

    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        function: String,
        line: Int
    ) {
        _ = level
        _ = file
        _ = function
        _ = line
        state.withLock { $0.messages.append(message()) }
    }

    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        let output = "\(message()) \(String(describing: context))"
        log(level, output, file: file, function: function, line: line)
    }
}

private final class PrivacyFailureEngine: LocalWhisperEngine {
    private let prepareError: (any Error)?
    private let streamError: (any Error)?

    init(prepareError: (any Error)? = nil, streamError: (any Error)? = nil) {
        self.prepareError = prepareError
        self.streamError = streamError
    }

    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        if let prepareError {
            throw prepareError
        }
        onProgress?(1)
    }

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        _ = languageCode
        _ = onPartial
        _ = onAudioLevel
        if let streamError {
            throw streamError
        }
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
        // Expected failure path.
    }
}
