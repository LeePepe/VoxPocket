import Foundation
import Synchronization
import VoxSpeech
import VoxCore
import XCTest
@testable import VoxSpeechWhisperKit

final class WhisperKitTranscriberBehaviorTests: XCTestCase {
    func testProviderTypeIsWhisper() {
        let sut = AsyncTestCoordinator.wrap(WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: NoopVoxLogger(),
            recorder: MicrophoneRecorder(logger: NoopVoxLogger(), storageLocations: testStorageLocations),
            telemetry: NoopVoxTelemetry(),
            engineFactory: { _, _ in FakeLocalWhisperEngine() }
        ))
        XCTAssertEqual(sut.core.providerKind, .whisper)
    }

    func testStartThenStopChangesState() async throws {
        let sut = AsyncTestCoordinator.wrap(WhisperKitTranscriber(
            config: .default,
            logger: NoopVoxLogger(),
            recorder: MicrophoneRecorder(logger: NoopVoxLogger(), storageLocations: testStorageLocations),
            telemetry: NoopVoxTelemetry(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in FakeLocalWhisperEngine() },
            autoPreload: true
        ))

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(sut.isTranscribing)

        await sut.stop()
        XCTAssertFalse(sut.isTranscribing)
    }

    func testStopKeepsBestPartialWhenLaterUpdateRegressesToShorterText() async throws {
        let engine = ScriptedLocalWhisperEngine()
        let sut = AsyncTestCoordinator.wrap(WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: NoopVoxLogger(),
            recorder: MicrophoneRecorder(logger: NoopVoxLogger(), storageLocations: testStorageLocations),
            telemetry: NoopVoxTelemetry(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in engine },
            autoPreload: false
        ))

        let finalTexts = Mutex<[String]>([])
        let cancellable = sut.observeFinals({ result in finalTexts.withLock { $0.append(result.text) } }
        )
        defer { cancellable.cancel() }

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        await engine.emitPartial("这个模型不错但是加载时间太久了有没有什么不错的")
        await engine.emitPartial("这个模型不错")
        await sut.stop()

        await assertEventually { finalTexts.withLock { $0.last } == "这个模型不错但是加载时间太久了有没有什么不错的" }
        XCTAssertEqual(finalTexts.withLock { $0.last }, "这个模型不错但是加载时间太久了有没有什么不错的")
    }

    func testLiveResultStripsWaitingForSpeechPlaceholder() async throws {
        let engine = ScriptedLocalWhisperEngine()
        let sut = AsyncTestCoordinator.wrap(WhisperKitTranscriber(
            config: LocalWhisperKitConfig(preloadOnStart: false),
            logger: NoopVoxLogger(),
            recorder: MicrophoneRecorder(logger: NoopVoxLogger(), storageLocations: testStorageLocations),
            telemetry: NoopVoxTelemetry(),
            permissionRequester: { true },
            hasPermissionProvider: { true },
            engineFactory: { _, _ in engine },
            autoPreload: false
        ))

        let liveTexts = Mutex<[String]>([])
        let cancellable = sut.observePartials({ result in liveTexts.withLock { $0.append(result.text) } }
        )
        defer { cancellable.cancel() }

        try await sut.start(language: Locale(identifier: "zh-Hans"))
        await engine.emitPartial("这个模型不错 Waiting for speech...")

        await assertEventually { liveTexts.withLock { $0.last } == "这个模型不错" }
        XCTAssertEqual(liveTexts.withLock { $0.last }, "这个模型不错")
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
    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? { nil }
    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? { nil }
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
    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? { nil }
    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? { nil }

    func emitPartial(_ text: String) async {
        await state.emitPartial(text)
    }
}
