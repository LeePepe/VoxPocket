import XCTest
import Combine
import Foundation
import Synchronization
import TranscriptionKit
@testable import UseCases

final class QuickRecordingReleaseUseCaseTests: XCTestCase {
    func testPreparedSourceFreezesBeforeStartupAndAwaitsDiscardWithoutOrdinaryStop() async throws {
        let source = QuickReleaseSource()
        let useCase = DefaultRecordingUseCase(coordinator: source)
        try useCase.prepareQuickRecording()
        let snapshot = try useCase.freezeQuickRecordingRelease()
        source.recognizeApple()
        XCTAssertFalse(snapshot.hasRecognizedSpeech)
        let entered = expectation(description: "discard entered")
        let gate = AsyncStream<Void>.makeStream()
        source.onDiscard = { entered.fulfill(); for await _ in gate.stream { break } }
        let completed = Mutex(false)
        let finish = Task { try await useCase.completeQuickRecordingRelease(snapshot); completed.withLock { $0 = true } }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertFalse(completed.withLock { $0 })
        XCTAssertEqual(source.events, ["prepare", "discard"])
        gate.continuation.finish()
        try await finish.value
        XCTAssertTrue(completed.withLock { $0 })
        try await useCase.completeQuickRecordingRelease(snapshot)
        XCTAssertEqual(source.events, ["prepare", "discard"])
    }

    func testEligibleReleaseUsesCapturedFallbackEvenAfterIdleResetsActiveSelection() async throws {
        let primary = LoadingQuickReleaseSource()
        let fallback = QuickReleaseSource()
        let useCase = DefaultRecordingUseCase(coordinator: primary, fallbackCoordinator: fallback)
        try useCase.prepareQuickRecording()
        try await useCase.startRecording()
        fallback.recognizeApple()
        let snapshot = try useCase.freezeQuickRecordingRelease()
        fallback.captureIdle()
        try await useCase.completeQuickRecordingRelease(snapshot)
        XCTAssertTrue(snapshot.hasRecognizedSpeech)
        XCTAssertTrue(primary.events.isEmpty)
        XCTAssertEqual(fallback.events, ["prepare", "start", "finish"])
    }

    func testOldTokenDoesNotAffectNewSessionAndNormalStopRemainsSeparate() async throws {
        let source = QuickReleaseSource()
        let useCase = DefaultRecordingUseCase(coordinator: source)
        try useCase.prepareQuickRecording()
        let old = try useCase.freezeQuickRecordingRelease()
        try await useCase.completeQuickRecordingRelease(old)
        try useCase.prepareQuickRecording()
        source.recognizeApple()
        let current = try useCase.freezeQuickRecordingRelease()
        try await useCase.completeQuickRecordingRelease(old)
        try await useCase.completeQuickRecordingRelease(current)
        try await useCase.startRecording()
        try await useCase.stopRecording()
        XCTAssertNotEqual(old.sessionID, current.sessionID)
        XCTAssertEqual(source.events, ["prepare", "discard", "prepare", "finish", "start", "ordinary stop"])
    }

    func testUnsupportedQuickCapabilityFailsWithoutStartingOrStopping() async {
        let source = OrdinaryReleaseSource()
        let useCase = DefaultRecordingUseCase(coordinator: source)
        XCTAssertThrowsError(try useCase.prepareQuickRecording())
        XCTAssertTrue(source.events.isEmpty)
    }

    func testDiscardFailureReleasesBridgeForNextSessionWithoutOrdinaryStop() async throws {
        let source = QuickReleaseSource()
        let useCase = DefaultRecordingUseCase(coordinator: source)
        try useCase.prepareQuickRecording()
        let snapshot = try useCase.freezeQuickRecordingRelease()
        source.onDiscard = { throw CancellationError() }
        do { try await useCase.completeQuickRecordingRelease(snapshot); XCTFail("Expected discard failure") }
        catch { XCTAssertTrue(error is CancellationError) }
        try useCase.prepareQuickRecording()
        XCTAssertEqual(source.events, ["prepare", "discard", "prepare"])
    }

    func testReleaseWaitsForSuspendedStartBeforeDiscard() async throws {
        let source = QuickReleaseSource()
        let useCase = DefaultRecordingUseCase(coordinator: source)
        let entered = expectation(description: "start entered")
        let gate = AsyncStream<Void>.makeStream()
        source.onStart = { entered.fulfill(); for await _ in gate.stream { break } }
        try useCase.prepareQuickRecording()
        let start = Task { try await useCase.startRecording() }
        await fulfillment(of: [entered], timeout: 1)
        let snapshot = try useCase.freezeQuickRecordingRelease()
        let finish = Task { try await useCase.completeQuickRecordingRelease(snapshot) }
        await Task.yield()
        XCTAssertEqual(source.events, ["prepare", "start"])
        gate.continuation.finish()
        try await start.value
        try await finish.value
        XCTAssertEqual(source.events, ["prepare", "start", "discard"])
        try useCase.prepareQuickRecording()
        XCTAssertEqual(source.events.last, "prepare")
    }
}

// Combine subjects bridge publishers; all mutable test state is protected by Mutex.
private class OrdinaryReleaseSource: TranscriptionCoordinator, AudioCaptureService,
    SpeechRecognitionService, @unchecked Sendable {
    private let eventState = Mutex<[String]>([])
    private let capture = CurrentValueSubject<AudioCaptureState, Never>(.idle)
    var events: [String] { eventState.withLock { $0 } }
    func record(_ event: String) { eventState.withLock { $0.append(event) } }
    var audioCaptureService: any AudioCaptureService { self }
    var speechRecognitionService: any SpeechRecognitionService { self }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { Empty().eraseToAnyPublisher() }
    var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> { Empty().eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { Empty().eraseToAnyPublisher() }
    var isTranscribing: Bool { false }
    func start(language: Locale) async throws { record("start") }
    func stop() async { record("ordinary stop") }
    func pause() {}
    func resume() {}
    var state: AudioCaptureState { capture.value }
    var statePublisher: AnyPublisher<AudioCaptureState, Never> { capture.eraseToAnyPublisher() }
    func captureIdle() { capture.send(.idle) }
    func startCapture() async throws {}
    func stopCapture() async {}
    func pauseCapture() {}
    func resumeCapture() {}
    func requestPermission() async -> Bool { true }
    var hasPermission: Bool { true }
    var providerType: ASRProviderType { .apple }
    var resultPublisher: AnyPublisher<TranscriptionResult, Error> { Empty().eraseToAnyPublisher() }
    func startRecognition(language: Locale) async throws {}
    func stopRecognition() async {}
    func checkAvailability() async -> Bool { true }
    var supportedLanguages: [Locale] { [] }
}

private class QuickReleaseSource: OrdinaryReleaseSource, QuickRecordingReleaseControlling, @unchecked Sendable {
    private struct State {
        var id = UUID()
        var eligible = false
        var frozen: QuickRecordingReleaseSnapshot?
        var onStart: (@Sendable () async -> Void)?
        var onDiscard: (@Sendable () async throws -> Void)?
    }
    private let release = Mutex(State())
    var onStart: (@Sendable () async -> Void)? {
        get { release.withLock { $0.onStart } }
        set { release.withLock { $0.onStart = newValue } }
    }
    var onDiscard: (@Sendable () async throws -> Void)? {
        get { release.withLock { $0.onDiscard } }
        set { release.withLock { $0.onDiscard = newValue } }
    }
    func prepareQuickRecording() throws {
        release.withLock { $0.id = UUID(); $0.eligible = false; $0.frozen = nil }
        record("prepare")
    }
    override func start(language: Locale) async throws { record("start"); await onStart?() }
    func recognizeApple() { release.withLock { if $0.frozen == nil { $0.eligible = true } } }
    func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        release.withLock {
            if let frozen = $0.frozen { return frozen }
            let frozen = QuickRecordingReleaseSnapshot(sessionID: $0.id, hasRecognizedSpeech: $0.eligible)
            $0.frozen = frozen
            return frozen
        }
    }
    func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        record(snapshot.hasRecognizedSpeech ? "finish" : "discard")
        if !snapshot.hasRecognizedSpeech { try await onDiscard?() }
    }
}

private final class LoadingQuickReleaseSource: QuickReleaseSource, ModelLoadingObservable, @unchecked Sendable {
    var modelLoadingState: ModelLoadingState { .loading }
    var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> { Just(.loading).eraseToAnyPublisher() }
}
