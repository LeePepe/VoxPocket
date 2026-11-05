import Combine
import Foundation
import Synchronization
import XCTest
import TranscriptionKit
import TranscriptionKitCombine
import VoxCore
import VoxKitBridge

final class CombineBridgeTests: XCTestCase {
    private var storage: VoxStorageLocations {
        VoxStorageLocations(temporaryAudio: FileManager.default.temporaryDirectory.appendingPathComponent("example-audio"),
                            modelCache: FileManager.default.temporaryDirectory.appendingPathComponent("example-models"))
    }
    func testEveryCoreTypePreservesIndependentCapabilities() throws {
        let apple = AppleSpeechTranscriber(storageLocations: storage)
        let whisper = WhisperKitTranscriber(config: .init(preloadOnStart: false), storageLocations: storage)
        let config = AzureWhisperConfig(endpoint: URL(string: "https://example.invalid")!, apiKey: "fixture")
        let rows: [(any SpeechSessionSource, Bool, Bool, Bool)] = [
            (apple, false, false, false),
            (AzureWhisperTranscriber(config: config, storageLocations: storage), false, false, false),
            (HybridWhisperTranscriber(whisperConfig: config, storageLocations: storage), true, false, false),
            (HybridLocalWhisperTranscriber(config: .init(preloadOnStart: false), storageLocations: storage), true, true, true),
            (whisper, false, true, false),
            (LoadingFallbackTranscriptionCoordinator(primary: whisper, fallback: apple), false, false, false),
            (DefaultSelectableTranscriptionCoordinator(permissionCoordinator: apple, factory: FixedFactory(source: apple)), false, false, false)
        ]
        for (core, multi, loading, start) in rows {
            let wrapper = CombineTranscriptionCoordinator.wrap(core)
            XCTAssertTrue(wrapper.core === core)
            XCTAssertEqual(wrapper is any MultiRecognizerTranscriber, multi)
            XCTAssertEqual(wrapper is any ModelLoadingObservable, loading)
            XCTAssertEqual(wrapper is any ModelLoadingStartControlling, start)
        }
    }

    func testPauseResumeAreSerializedAndStopWaitsForQueue() async throws {
        let session = ProbeSession()
        let source = ProbeSource(session: session)
        let wrapper = CombineTranscriptionCoordinator.wrap(source)
        try await wrapper.start(language: Locale(identifier: "zh-Hans"))
        wrapper.pause()
        wrapper.resume()
        wrapper.pause()
        wrapper.resume()
        await wrapper.stop()
        let operations = await session.operations
        XCTAssertEqual(operations, ["pause", "resume", "pause", "resume", "stop"])
    }

    func testPreSessionSubscriptionsAndTypedEventForwarding() async throws {
        let session = ProbeSession()
        let source = ProbeSource(session: session)
        let wrapper = CombineTranscriptionCoordinator.wrap(source)
        let capture = expectation(description: "capture before session")
        let level = expectation(description: "level before session")
        let final = expectation(description: "final")
        let subscriptions = [
            wrapper.audioCaptureService.statePublisher.sink { if $0 == .paused { capture.fulfill() } },
            wrapper.audioLevelPublisher.sink { if $0 == 0.75 { level.fulfill() } },
            wrapper.finalResultPublisher.sink(receiveCompletion: { _ in }) { result in
                XCTAssertEqual(result.text, "synthetic final")
                final.fulfill()
            }
        ]
        source.stateContinuation.yield(.paused)
        source.levelContinuation.yield(0.75)
        await fulfillment(of: [capture, level], timeout: 2)
        try await wrapper.start(language: .current)
        session.continuation.yield(.final(.init(text: "synthetic final", type: .final, locale: .current)))
        await fulfillment(of: [final], timeout: 2)
        withExtendedLifetime(subscriptions) {}
    }

    func testCredentialsUseInjectedSnapshot() {
        let credentials = EnvironmentCredentialProvider(snapshot: [.azureSpeechKey: Credential(rawValue: "fixture-key")])
        XCTAssertEqual(credentials.credential(for: .azureSpeechKey)?.rawValue, "fixture-key")
        XCTAssertNil(credentials.credential(for: .llmAPIKey))
        XCTAssertEqual(String(describing: credentials.credential(for: .azureSpeechKey)!), "Credential(<redacted>)")
    }
}

private struct FixedFactory: SpeechSessionFactory {
    let source: any SpeechSessionSource
    func makeSource() async throws -> any SpeechSessionSource { source }
}

private actor ProbeSession: SpeechSession {
    nonisolated let stream: AsyncThrowingStream<TranscriptionEvent, Error>
    nonisolated let continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
    private(set) var operations: [String] = []
    init() {
        let pair = AsyncThrowingStream<TranscriptionEvent, Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }
    nonisolated func events() -> AsyncThrowingStream<TranscriptionEvent, Error> { stream }
    func pause() async { operations.append("pause"); await Task.yield() }
    func resume() async { operations.append("resume"); await Task.yield() }
    func stop() async { operations.append("stop") }
    func cancel() async { operations.append("cancel"); continuation.finish(throwing: CancellationError()) }
}

private final class ProbeSource: SpeechSessionSource {
    let session: ProbeSession
    let stateStream: AsyncStream<AudioCaptureState>
    let stateContinuation: AsyncStream<AudioCaptureState>.Continuation
    let levelStream: AsyncStream<Float>
    let levelContinuation: AsyncStream<Float>.Continuation
    init(session: ProbeSession) {
        self.session = session
        (stateStream, stateContinuation) = AsyncStream.makeStream()
        (levelStream, levelContinuation) = AsyncStream.makeStream()
    }
    var providerKind: ASRProviderType { .custom }
    var supportedLanguages: [Locale] { [.current] }
    var isActive: Bool { false }
    var hasMicrophonePermission: Bool { true }
    var hasSpeechPermission: Bool { true }
    func requestMicrophonePermission() async -> Bool { true }
    func requestSpeechPermission() async -> Bool { true }
    func captureStates() -> AsyncStream<AudioCaptureState> { stateStream }
    func audioLevels() -> AsyncStream<Float> { levelStream }
    func startSession(language: Locale) async throws -> any SpeechSession { session }
}
