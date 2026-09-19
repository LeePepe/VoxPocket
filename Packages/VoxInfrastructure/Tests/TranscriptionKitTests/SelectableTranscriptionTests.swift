import Combine
import Foundation
import Synchronization
import XCTest
@testable import TranscriptionKit

final class SelectableTranscriptionTests: XCTestCase {
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
    func stop() async { running.withLock { $0 = false } }
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
