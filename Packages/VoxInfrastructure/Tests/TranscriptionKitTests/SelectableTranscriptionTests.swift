import Combine
import Foundation
import Synchronization
import XCTest
@testable import TranscriptionKit

final class SelectableTranscriptionTests: XCTestCase {
    func testQuickReleaseBeforeRouterStartNeverRunsSelection() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.apple.make(probe)
        let selections = Mutex(0)
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: source) {
            selections.withLock { $0 += 1 }; return source
        }
        try router.prepareQuickRecording()
        let frozen = try router.freezeQuickRecordingRelease()
        do { try await router.start(language: .current); XCTFail("Released startup must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await router.completeQuickRecordingRelease(frozen)
        XCTAssertEqual(selections.withLock { $0 }, 0)
        XCTAssertEqual(probe.count("start"), 0)
        try router.prepareQuickRecording()
    }

    func testEligibleQuickAppleRetainsFinalAndOldRouterTokenCannotStopNextSession() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.apple.make(probe)
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: source) { source }
        let finals = Mutex(0)
        let subscription = router.finalResultPublisher.sink(receiveCompletion: { _ in }, receiveValue: { _ in
            finals.withLock { $0 += 1 }
        })
        defer { subscription.cancel() }
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        probe.send("synthetic apple")
        let old = try router.freezeQuickRecordingRelease()
        try await router.completeQuickRecordingRelease(old)
        probe.send("synthetic delayed final", type: .final)
        XCTAssertEqual(finals.withLock { $0 }, 1)
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        probe.send("stale synthetic apple", type: .final, index: 0)
        try await router.completeQuickRecordingRelease(old)
        XCTAssertTrue(router.isTranscribing)
        let next = try router.freezeQuickRecordingRelease()
        XCTAssertFalse(next.hasRecognizedSpeech)
        try await router.completeQuickRecordingRelease(next)
        XCTAssertEqual(finals.withLock { $0 }, 1)
    }

    func testQuickRouterRemainsOccupiedUntilDiscardCleanupCompletes() async throws {
        let gate = QuickRecordingEffectGate()
        let probe = QuickRecordingEffectProbe(cleanupGate: gate)
        let source = QuickRecordingTestProvider.apple.make(probe)
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: source) { source }
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        let frozen = try router.freezeQuickRecordingRelease()
        let completing = Task { try await router.completeQuickRecordingRelease(frozen) }
        await gate.entered()
        XCTAssertThrowsError(try router.prepareQuickRecording())
        await gate.release()
        try await completing.value
        try router.prepareQuickRecording()
    }

    func testQuickRouterForwardsFrozenSourceDecisionAndSealsDiscardedOutput() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let probe = QuickRecordingEffectProbe(realtime: provider == .realtime)
            let source = provider.make(probe)
            let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: source) { source }
            let finals = Mutex(0)
            let subscription = router.finalResultPublisher.sink(receiveCompletion: { _ in }, receiveValue: { _ in
                finals.withLock { $0 += 1 }
            })
            try router.prepareQuickRecording()
            try await router.start(language: .current)
            let frozen = try router.freezeQuickRecordingRelease()
            probe.send("late synthetic apple", type: .final)
            try await router.completeQuickRecordingRelease(frozen)
            probe.send("late synthetic final", type: .final)
            XCTAssertEqual(finals.withLock { $0 }, 0)
            XCTAssertEqual(probe.count("batch"), 0)
            XCTAssertEqual(probe.count("endApple"), 0)
            XCTAssertEqual(probe.count("stop"), 1)
            subscription.cancel()
        }
    }

    func testQuickReleaseDuringSelectionNeverStartsChosenSource() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.apple.make(probe)
        let gate = FakeSelectionGate()
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: source) {
            await gate.wait(); return source
        }
        try router.prepareQuickRecording()
        let starting = Task { try await router.start(language: .current) }
        await gate.entered()
        let frozen = try router.freezeQuickRecordingRelease()
        let completing = Task { try await router.completeQuickRecordingRelease(frozen) }
        await gate.release()
        _ = await starting.result
        try await completing.value
        XCTAssertEqual(probe.count("start"), 0)
        XCTAssertEqual(probe.count("endApple"), 0)
        XCTAssertFalse(router.isTranscribing)
        try router.prepareQuickRecording()
    }

    func testQuickEligibleDecisionCanBeExplicitlyDiscardedThroughRouter() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.apple.make(probe)
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: source) { source }
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        probe.send("synthetic apple")
        let frozen = try router.freezeQuickRecordingRelease()
        XCTAssertTrue(frozen.hasRecognizedSpeech)
        try await router.completeQuickRecordingRelease(.init(sessionID: frozen.sessionID, hasRecognizedSpeech: false))
        XCTAssertEqual(probe.count("cancelApple"), 1)
        XCTAssertEqual(probe.count("endApple"), 0)
    }

    func testQuickUnsupportedSourceFailsWithoutStartingOrNormalStop() async throws {
        let source = FakeSelectableTranscriber()
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: source) { source }
        try router.prepareQuickRecording()
        do { try await router.start(language: .current); XCTFail("Expected unsupported capability") }
        catch { XCTAssertTrue(error is QuickRecordingReleaseError) }
        XCTAssertEqual(source.startCount.withLock { $0 }, 0)
        XCTAssertEqual(source.stopCount.withLock { $0 }, 0)
        try router.prepareQuickRecording()
    }

    func testSupportedQuickStartupFailureCleansAndAllowsImmediateNextSession() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let failed = QuickRecordingEffectProbe(startFails: true)
            let failedSource = provider.make(failed)
            let selection = Mutex<any TranscriptionCoordinator>(failedSource)
            let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: failedSource) {
                selection.withLock { $0 }
            }
            try router.prepareQuickRecording()
            do { try await router.start(language: .current); XCTFail("Expected startup failure") }
            catch { XCTAssertTrue(error is QuickRecordingReleaseError) }
            XCTAssertEqual(failed.count("stop"), 1)
            XCTAssertEqual(failed.count("cancelApple"), 1)
            XCTAssertEqual(failed.count("removeAudio"), 1)
            XCTAssertEqual(failed.count("endApple"), 0)
            XCTAssertEqual(failed.count("batch"), 0)
            let next = QuickRecordingEffectProbe()
            selection.withLock { $0 = provider.make(next) }
            try router.prepareQuickRecording()
            try await router.start(language: .current)
            failed.send("stale Apple", type: .final)
            let frozen = try router.freezeQuickRecordingRelease()
            XCTAssertFalse(frozen.hasRecognizedSpeech)
            try await router.completeQuickRecordingRelease(frozen)
            XCTAssertEqual(next.count("stop"), 1)
        }
    }

    func testSystemSpeechFinalCanArriveAfterStopReturns() async throws {
        let fake = FakeSelectableTranscriber()
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: fake) { fake }
        let seen = Mutex<[String]>([])
        let subscription = router.finalResultPublisher.sink(receiveCompletion: { _ in }, receiveValue: { value in
            seen.withLock { $0.append(value.text) }
        })
        defer { subscription.cancel() }
        try await router.start(language: .current)
        await router.stop()
        XCTAssertFalse(router.isTranscribing)
        fake.sendFinal("delayed system final")
        XCTAssertEqual(seen.withLock { $0 }, ["delayed system final"])
    }

    func testSelectionChangesOnNextStartAndOldPublishersAreIsolated() async throws {
        let first = FakeSelectableTranscriber()
        let second = FakeSelectableTranscriber()
        let selection = Mutex<any TranscriptionCoordinator>(first)
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: first) { selection.withLock { $0 } }
        let received = Mutex<[String]>([])
        let finals = router.finalResultPublisher.sink(receiveCompletion: { _ in }, receiveValue: { value in
            received.withLock { $0.append(value.text) }
        })
        defer { finals.cancel() }
        try await router.start(language: .current)
        selection.withLock { $0 = second }
        XCTAssertTrue(first.isTranscribing)
        XCTAssertFalse(second.isTranscribing)
        first.sendFinal("first")
        await router.stop()
        try await router.start(language: .current)
        first.sendFinal("stale")
        second.sendFinal("second")
        XCTAssertEqual(received.withLock { $0 }, ["first", "second"])
        await router.stop()
        XCTAssertFalse(router.isTranscribing)
    }

    func testStopDuringFactoryWaitNeverStartsMicrophone() async throws {
        let fake = FakeSelectableTranscriber()
        let gate = FakeSelectionGate()
        let cancelled = expectation(description: "selection lookup cancelled")
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: fake) {
            await withTaskCancellationHandler { await gate.wait() } onCancel: { cancelled.fulfill() }
            return fake
        }
        let starting = Task { try await router.start(language: .current) }
        await gate.entered()
        let stopping = Task { await router.stop() }
        await fulfillment(of: [cancelled], timeout: 1)
        await gate.release()
        _ = await starting.result
        await stopping.value
        XCTAssertFalse(fake.isTranscribing)
        XCTAssertEqual(fake.startCount.withLock { $0 }, 0)
        XCTAssertFalse(router.isTranscribing)
    }

    func testBackendFailureDoesNotTerminateSubsequentRecordings() async throws {
        let first = FakeSelectableTranscriber()
        let second = FakeSelectableTranscriber()
        let selection = Mutex<any TranscriptionCoordinator>(first)
        let router = DefaultSelectableTranscriptionCoordinator(permissionCoordinator: first) { selection.withLock { $0 } }
        let seen = Mutex<[String]>([])
        let subscriber = router.liveResultPublisher.sink(receiveCompletion: { _ in XCTFail("Shared stream must remain usable") },
                                                        receiveValue: { value in seen.withLock { $0.append(value.text) } })
        defer { subscriber.cancel() }
        try await router.start(language: .current)
        first.fail()
        XCTAssertEqual(router.state, .error("语音识别失败，请重试。"))
        await router.stop()
        selection.withLock { $0 = second }
        try await router.start(language: .current)
        second.sendLive("next")
        XCTAssertEqual(seen.withLock { $0 }, ["next"])
        await router.stop()
    }
}

// Combine publisher 测试桥接；可变运行状态使用 Mutex。
private final class FakeSelectableTranscriber: TranscriptionCoordinator, AudioCaptureService,
    SpeechRecognitionService, @unchecked Sendable {
    private let running = Mutex(false)
    let startCount = Mutex(0)
    let stopCount = Mutex(0)
    private let live = PassthroughSubject<TranscriptionResult, Error>()
    private let final = PassthroughSubject<TranscriptionResult, Error>()
    var audioCaptureService: any AudioCaptureService { self }
    var speechRecognitionService: any SpeechRecognitionService { self }
    var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> { live.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { final.eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { Just(0).eraseToAnyPublisher() }
    var statePublisher: AnyPublisher<AudioCaptureState, Never> { Just(.idle).eraseToAnyPublisher() }
    var state: AudioCaptureState { .idle }
    var isTranscribing: Bool { running.withLock { $0 } }
    var providerType: ASRProviderType { .custom }
    var resultPublisher: AnyPublisher<TranscriptionResult, Error> { liveResultPublisher }
    var supportedLanguages: [Locale] { [.current] }
    var hasPermission: Bool { true }
    func start(language: Locale) async throws {
        startCount.withLock { $0 += 1 }
        running.withLock { $0 = true }
    }
    func stop() async { stopCount.withLock { $0 += 1 }; running.withLock { $0 = false } }
    func pause() {}
    func resume() {}
    func startCapture() async throws {}
    func stopCapture() async {}
    func pauseCapture() {}
    func resumeCapture() {}
    func requestPermission() async -> Bool { true }
    func startRecognition(language: Locale) async throws {}
    func stopRecognition() async {}
    func checkAvailability() async -> Bool { true }
    func sendLive(_ text: String) { live.send(.init(text: text, type: .partial, locale: .current)) }
    func sendFinal(_ text: String) { final.send(.init(text: text, type: .final, locale: .current)) }
    func fail() { live.send(completion: .failure(RealtimeTranscriptionError.connectionFailed)) }
}

private actor FakeSelectionGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            observers.forEach { $0.resume() }; observers.removeAll()
        }
    }
    func entered() async {
        if waiting != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { waiting?.resume(); waiting = nil }
}
