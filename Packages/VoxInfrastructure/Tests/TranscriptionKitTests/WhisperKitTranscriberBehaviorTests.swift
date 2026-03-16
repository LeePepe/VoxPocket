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

    func testStopKeepsBestPartialWhenLaterUpdateRegressesToShorterText() async throws {
        let engine = ScriptedLocalWhisperEngine()
        let sut = WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: PrintLogger(subsystem: "WhisperKitTranscriberTests"),
            recorder: MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitTranscriberTests.Mic")),
            telemetry: NoopTelemetryService(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in engine },
            autoPreload: false
        )

        var finalTexts: [String] = []
        let cancellable = sut.finalResultPublisher.sink(
            receiveCompletion: { _ in },
            receiveValue: { finalTexts.append($0.text) }
        )
        defer { cancellable.cancel() }

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        await engine.emitPartial("这个模型不错但是加载时间太久了有没有什么不错的")
        await engine.emitPartial("这个模型不错")
        await sut.stop()

        XCTAssertEqual(finalTexts.last, "这个模型不错但是加载时间太久了有没有什么不错的")
    }

    func testStopPublishesAudioEndedAndRecognitionCompletedLifecycleEvents() async throws {
        let engine = ScriptedLocalWhisperEngine()
        let sut = WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: PrintLogger(subsystem: "WhisperKitTranscriberTests"),
            recorder: MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitTranscriberTests.Mic")),
            telemetry: NoopTelemetryService(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in engine },
            autoPreload: false
        )

        var events: [TranscriptionLifecycleEvent] = []
        let cancellable = sut.lifecycleEventPublisher.sink { events.append($0) }
        defer { cancellable.cancel() }

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        await engine.emitPartial("你好世界")
        await sut.stop()

        XCTAssertTrue(events.contains(.audioEnded))
        XCTAssertEqual(events.suffix(2), [.audioEnded, .recognitionCompleted])
    }

    func testLiveResultStripsWaitingForSpeechPlaceholder() async throws {
        let engine = ScriptedLocalWhisperEngine()
        let sut = WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: PrintLogger(subsystem: "WhisperKitTranscriberTests"),
            recorder: MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitTranscriberTests.Mic")),
            telemetry: NoopTelemetryService(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in engine },
            autoPreload: false
        )

        var liveTexts: [String] = []
        let cancellable = sut.liveResultPublisher.sink(
            receiveCompletion: { _ in },
            receiveValue: { liveTexts.append($0.text) }
        )
        defer { cancellable.cancel() }

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        await engine.emitPartial("这个模型不错 Waiting for speech...")

        XCTAssertEqual(liveTexts.last, "这个模型不错")
    }

    func testSpeechDetectedLifecycleEventOnlyPublishesOnce() async throws {
        let engine = ScriptedLocalWhisperEngine()
        let sut = WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: PrintLogger(subsystem: "WhisperKitTranscriberTests"),
            recorder: MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitTranscriberTests.Mic")),
            telemetry: NoopTelemetryService(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in engine },
            autoPreload: false
        )

        var events: [TranscriptionLifecycleEvent] = []
        let cancellable = sut.lifecycleEventPublisher.sink { events.append($0) }
        defer { cancellable.cancel() }

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        await engine.emitPartial("你好")
        await engine.emitPartial("你好世界")

        XCTAssertEqual(events.filter { $0 == .speechDetected }.count, 1)
    }
}

private final class FakeLocalWhisperEngine: LocalWhisperEngine {
    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        _ = onProgress
    }

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

private final class ScriptedLocalWhisperEngine: LocalWhisperEngine {
    private actor State {
        var onPartial: (@Sendable (String) -> Void)?
        var onAudioLevel: (@Sendable (Float) -> Void)?

        func setCallbacks(
            onPartial: @escaping @Sendable (String) -> Void,
            onAudioLevel: @escaping @Sendable (Float) -> Void
        ) {
            self.onPartial = onPartial
            self.onAudioLevel = onAudioLevel
        }

        func emitPartial(_ text: String) {
            onPartial?(text)
        }
    }

    private let state = State()

    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        onProgress?(1.0)
    }

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        _ = languageCode
        await state.setCallbacks(onPartial: onPartial, onAudioLevel: onAudioLevel)
        onAudioLevel(0.2)
    }

    func stopStreaming() async {}
    func pauseStreaming() async {}
    func resumeStreaming() async {}

    func emitPartial(_ text: String) async {
        await state.emitPartial(text)
    }
}
