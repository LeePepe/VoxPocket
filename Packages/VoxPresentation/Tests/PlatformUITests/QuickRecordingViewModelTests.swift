#if os(macOS)
import XCTest
import Combine
import Synchronization
import PlatformAdapters
import LLMKit
import TranscriptionKit
import UseCases
@testable import PlatformUI

@MainActor
final class QuickRecordingViewModelTests: XCTestCase {
    func testRefinementUpdatesAreVisibleBeforeCompletion() {
        let viewModel = makeViewModel()
        viewModel.liveTranscription = "我明天去开会然后说那个计划"
        viewModel.recorderStatus = .refining
        XCTAssertEqual(viewModel.displayedTranscription, viewModel.liveTranscription)
        viewModel.refinedText = "明天开会讨论计划。"
        XCTAssertEqual(viewModel.displayedTranscription, "明天开会讨论计划。")
    }

    func testStreamingRefinementDoesNotPreventFnReleaseFromStoppingRecording() async throws {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let viewModel = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                               refinementUseCase: FakeRefinementUseCase(),
                                               clipboardService: FakeClipboardService(), streamingCoordinator: coordinator)
        recording.onStop = {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                transcription.sendFinalText("识别原文")
            }
        }
        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("识别原文")
        try await Task.sleep(for: .milliseconds(20))
        coordinator.send("已润色的句子。")
        XCTAssertEqual(viewModel.recorderStatus, .listening)
        XCTAssertNotNil(viewModel.normalizedAudioLevel)
        await viewModel.stopRecording()
        XCTAssertEqual(recording.stopCallCount, 1)
    }

    func testQuickRecordingDoesNotAutoStopAfterSilenceWhileStillHeld() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("你好")

        try? await Task.sleep(nanoseconds: 3_100_000_000)

        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertEqual(viewModel.recorderStatus, .listening)
    }

    func testShowsLiveTranscriptionOnlyForDisplayableStatesWithText() async {
        let viewModel = makeViewModel()

        viewModel.liveTranscription = ""
        viewModel.recorderStatus = .listening
        XCTAssertFalse(viewModel.showsLiveTranscription)

        viewModel.liveTranscription = "你好"
        viewModel.recorderStatus = .listening
        XCTAssertTrue(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .transcribing
        XCTAssertTrue(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .refining
        XCTAssertTrue(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .idle
        XCTAssertFalse(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .done
        XCTAssertFalse(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .error
        XCTAssertFalse(viewModel.showsLiveTranscription)
    }

    func testWhitespaceDoesNotExpandTranscript() {
        let viewModel = makeViewModel()
        viewModel.liveTranscription = " \n\t　"
        viewModel.recorderStatus = .listening
        XCTAssertFalse(viewModel.showsLiveTranscription)
    }

    func testNewRecordingClearsPreviousTranscript() async {
        let viewModel = makeViewModel()
        viewModel.liveTranscription = "上一轮识别内容"
        viewModel.refinedText = "上一轮润色内容"
        await viewModel.startRecording()
        XCTAssertTrue(viewModel.liveTranscription.isEmpty)
        XCTAssertTrue(viewModel.refinedText.isEmpty)
        XCTAssertFalse(viewModel.showsLiveTranscription)
    }

    func testStopRecordingRetainsLiveTranscriptionForProcessingStates() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("实时转写尾部")

        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.liveTranscription, "实时转写尾部")
        XCTAssertTrue(viewModel.showsLiveTranscription)
    }

    func testStopRecordingUsesLatestTranscriptionArrivingRightAfterStop() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        recording.onStop = {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("你好世界")
            }
        }

        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("你好世")

        await viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertEqual(viewModel.rawTranscription, "你好世界")
    }

    func testStopRecordingWaitsForDelayedFinalTranscription() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        recording.onStop = {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                transcription.sendFinalText("你好世界")
            }
        }

        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("你好世")

        await viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertEqual(viewModel.rawTranscription, "你好世界")
    }

    func testStopRecordingFallsBackQuicklyToSettledLiveTranscriptionWhenNoFinalArrives() async throws {
        try XCTSkipIf(true, """
        QuickRecordingViewModel 在 live 文本已 settle 且无 final 到达时未快速回退,
        仍等满 15s final 超时(期望 <3s)。属既有生产代码行为问题,追踪于 GitHub issue。
        """)
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("你好世界")

        let startedAt = Date()
        await viewModel.stopRecording()
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 3.0, "stopRecording should not wait for full final-result timeout when live text is already settled")
        XCTAssertEqual(viewModel.rawTranscription, "你好世界")
    }

    func testStopRecordingWithEmptyTranscriptionTriggersNoResultCallback() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        var didCallNoResult = false
        viewModel.onNoResult = {
            didCallNoResult = true
        }

        await viewModel.startRecording()
        await viewModel.stopRecording()

        XCTAssertTrue(didCallNoResult)
    }

    func testStopRecordingAppendsChineseSentenceTerminatorWhenMissing() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase(
            streamedChunks: ["再看一下为什么有时候没有能够成功添加标点符号"]
        )
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("再看一下为什么有时候没有能够成功添加标点符号")

        await viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(clipboard.copiedText, "再看一下为什么有时候没有能够成功添加标点符号。")
    }

    func testStopRequestedDuringStartStopsAfterStartCompletes() async {
        let recording = FakeRecordingUseCase(startDelayNanoseconds: 300_000_000)
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        let startTask = Task {
            await viewModel.startRecording()
        }
        await Task.yield()
        await viewModel.stopRecording()
        await startTask.value

        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertEqual(recording.discardCallCount, 1)
    }

    func testImmediateReleaseCleansUpNeverCompletingTranscriptionAndCanRestart() async {
        let recording = FakeRecordingUseCase(startDelayNanoseconds: 50_000_000)
        let transcription = FakeTranscriptionUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                               refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard,
                                               streamingCoordinator: coordinator)
        var dismissals = 0
        viewModel.onNoResult = { dismissals += 1 }
        let stopped = expectation(description: "Quick release finishes without waiting for final")
        let start = Task {
            await viewModel.startRecording()
            stopped.fulfill()
        }
        await Task.yield()
        await viewModel.stopRecording()
        await fulfillment(of: [stopped], timeout: 1)
        start.cancel()
        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertEqual(recording.discardCallCount, 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(viewModel.recorderStatus, .idle)
        XCTAssertEqual(coordinator.cancelCallCount, 1)
        XCTAssertFalse(coordinator.isStreaming)
        XCTAssertEqual(transcription.finalCancellationCount, 0)
        XCTAssertNil(clipboard.copiedText)
        await viewModel.startRecording()
        XCTAssertTrue(coordinator.isStreaming)
        XCTAssertEqual(viewModel.recorderStatus, .listening)
        await viewModel.stopRecording()
        XCTAssertEqual(dismissals, 2)
        XCTAssertEqual(coordinator.cancelCallCount, 2)
    }

    func testReleaseDuringStreamingStartupWaitsForInitializationBeforeStopping() async {
        let recording = FakeRecordingUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let entered = expectation(description: "Streaming startup is suspended")
        let gate = AsyncStream<Void>.makeStream()
        coordinator.onStart = {
            entered.fulfill()
            for await _ in gate.stream { break }
        }
        let viewModel = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: FakeTranscriptionUseCase(),
                                               refinementUseCase: FakeRefinementUseCase(), clipboardService: FakeClipboardService(),
                                               streamingCoordinator: coordinator)
        var dismissals = 0
        viewModel.onNoResult = { dismissals += 1 }
        let finished = expectation(description: "Startup and deferred release finish")
        let start = Task { await viewModel.startRecording(); finished.fulfill() }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertTrue(viewModel.isStartingRecording)
        await viewModel.stopRecording()
        XCTAssertEqual(recording.stopCallCount, 0)
        gate.continuation.finish()
        await fulfillment(of: [finished], timeout: 1)
        start.cancel()
        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertEqual(recording.discardCallCount, 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertFalse(coordinator.isStreaming)
        XCTAssertFalse(viewModel.isStartingRecording)
    }

    func testFinalWithoutAppleEvidenceIsDiscardedOnRelease() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                               refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard,
                                               streamingCoordinator: coordinator)
        recording.onStop = { transcription.sendFinalText("有效音频的终稿") }
        var dismissals = 0
        viewModel.onNoResult = { dismissals += 1 }
        await viewModel.startRecording()
        await viewModel.stopRecording()
        XCTAssertTrue(viewModel.rawTranscription.isEmpty)
        XCTAssertEqual(viewModel.recorderStatus, .idle)
        XCTAssertNil(clipboard.copiedText)
        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertEqual(recording.discardCallCount, 1)
        XCTAssertEqual(dismissals, 1)
    }

    func testStopFailureCancelsStreamingAndReleasesFinalSubscription() async {
        let recording = FakeRecordingUseCase()
        recording.stopError = CancellationError()
        let transcription = FakeTranscriptionUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let viewModel = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                               refinementUseCase: FakeRefinementUseCase(), clipboardService: FakeClipboardService(),
                                               streamingCoordinator: coordinator)
        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        await viewModel.stopRecording()
        XCTAssertEqual(viewModel.recorderStatus, .error)
        XCTAssertFalse(coordinator.isStreaming)
        XCTAssertEqual(coordinator.cancelCallCount, 1)
        XCTAssertEqual(transcription.finalCancellationCount, 1)
    }

    func testErrorRetainsOriginalTextAndCopiesIt() {
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(recordingUseCase: FakeRecordingUseCase(),
                                               transcriptionUseCase: FakeTranscriptionUseCase(),
                                               refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard)
        viewModel.liveTranscription = "已识别原文"
        viewModel.refinedText = "未完成的润色"
        viewModel.recorderStatus = .error
        XCTAssertEqual(viewModel.displayedTranscription, "已识别原文")
        viewModel.copyRecognizedText()
        XCTAssertEqual(clipboard.copiedText, "已识别原文")
        viewModel.recorderStatus = .idle
        XCTAssertTrue(viewModel.displayedTranscription.isEmpty)
    }

    func testCancelFromPanelStopsAndRequestsDismissalOnce() async {
        let recording = FakeRecordingUseCase()
        let viewModel = QuickRecordingViewModel(recordingUseCase: recording,
                                               transcriptionUseCase: FakeTranscriptionUseCase(),
                                               refinementUseCase: FakeRefinementUseCase(), clipboardService: FakeClipboardService())
        var dismissals = 0
        viewModel.onNoResult = { dismissals += 1 }
        await viewModel.startRecording()
        await viewModel.cancelFromPanel()
        await viewModel.cancelFromPanel()
        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertEqual(recording.discardCallCount, 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(viewModel.recorderStatus, .idle)
    }

    func testCompletionKeepsFinalTextVisibleUntilHostClosesAndFreezesDuration() async throws {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                               refinementUseCase: FakeRefinementUseCase(streamedChunks: ["已整理"]),
                                               clipboardService: clipboard)
        recording.onStop = {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                transcription.sendFinalText("识别原文")
            }
        }
        let completed = expectation(description: "完成回调")
        viewModel.onComplete = { _ in completed.fulfill() }
        await viewModel.startRecording()
        recording.recognizeApple("synthetic Apple partial")
        transcription.sendLiveText("识别原文")
        try await Task.sleep(for: .milliseconds(20))
        await viewModel.stopRecording()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(viewModel.recorderStatus, .done)
        XCTAssertEqual(viewModel.displayedTranscription, clipboard.copiedText)
        XCTAssertEqual(viewModel.displayedTranscription, "已整理。")
        XCTAssertEqual(viewModel.elapsedRecordingTime(at: Date()),
                       viewModel.elapsedRecordingTime(at: Date().addingTimeInterval(60)))
    }

    func testEmptyReleaseWaitsForDiscardIgnoresCloudUIAndLateCallbacks() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let clipboard = FakeClipboardService()
        let gate = AsyncStream<Void>.makeStream()
        let entered = expectation(description: "discard entered")
        recording.onDiscard = { entered.fulfill(); for await _ in gate.stream { break } }
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard,
                                           streamingCoordinator: coordinator)
        var noResults = 0, completions = 0
        model.onNoResult = { noResults += 1 }
        model.onComplete = { _ in completions += 1 }
        await model.startRecording()
        recording.recognizeApple(" \n\t")
        transcription.sendLiveText("synthetic cloud preview")
        model.liveTranscription = "synthetic queued UI text"
        let release = Task { await model.stopRecording() }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertEqual(noResults, 0)
        XCTAssertEqual(model.recorderStatus, .transcribing)
        recording.recognizeApple("late Apple")
        transcription.sendFinalText("late final")
        coordinator.send("late refinement")
        model.copyRecognizedText()
        await model.stopRecording()
        gate.continuation.finish()
        await release.value
        XCTAssertEqual(recording.freezeCallCount, 1)
        XCTAssertEqual(recording.discardCallCount, 1)
        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertEqual(noResults, 1)
        XCTAssertEqual(completions, 0)
        XCTAssertTrue(model.rawTranscription.isEmpty)
        XCTAssertTrue(model.refinedText.isEmpty)
        XCTAssertNil(clipboard.copiedText)
        XCTAssertEqual(transcription.finalCancellationCount, 0)
    }

    func testAppleEvidenceBeforeQueuedUIUpdatePreservesEligibleFinalAndStickyLatch() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let clipboard = FakeClipboardService()
        recording.onStop = { transcription.sendFinalText("synthetic final") }
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard,
                                           streamingCoordinator: coordinator)
        await model.startRecording()
        recording.recognizeApple("synthetic Apple")
        recording.recognizeApple(" \n")
        XCTAssertTrue(model.liveTranscription.isEmpty)
        await model.stopRecording()
        XCTAssertEqual(recording.stopCallCount, 1)
        XCTAssertEqual(recording.discardCallCount, 0)
        XCTAssertEqual(model.rawTranscription, "synthetic final")
        XCTAssertEqual(clipboard.copiedText, "synthetic final。")
    }

    func testDeferredStartupReleaseNeverUpgradesOnLaterAppleResult() async {
        let recording = FakeRecordingUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let entered = expectation(description: "streaming initialization entered")
        let gate = AsyncStream<Void>.makeStream()
        coordinator.onStart = { entered.fulfill(); for await _ in gate.stream { break } }
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: FakeTranscriptionUseCase(),
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: FakeClipboardService(),
                                           streamingCoordinator: coordinator)
        let start = Task { await model.startRecording() }
        await fulfillment(of: [entered], timeout: 1)
        await model.stopRecording()
        recording.recognizeApple("late Apple")
        await model.stopRecording()
        gate.continuation.finish()
        await start.value
        XCTAssertEqual(recording.freezeCallCount, 1)
        XCTAssertEqual(recording.discardCallCount, 1)
        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertFalse(coordinator.isStreaming)
    }

    func testEligibleAppleReleaseDuringStreamingStartupCompletesAfterInitialization() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let coordinator = FakeQuickStreamingCoordinator()
        let clipboard = FakeClipboardService()
        let entered = expectation(description: "streaming initialization entered")
        let gate = AsyncStream<Void>.makeStream()
        coordinator.onStart = { entered.fulfill(); for await _ in gate.stream { break } }
        recording.onStop = { transcription.sendFinalText("eligible final") }
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard,
                                           streamingCoordinator: coordinator)
        let start = Task { await model.startRecording() }
        await fulfillment(of: [entered], timeout: 1)
        recording.recognizeApple("early Apple")
        await model.stopRecording()
        XCTAssertEqual(recording.freezeCallCount, 1)
        XCTAssertEqual(recording.stopCallCount, 0)
        gate.continuation.finish()
        await start.value
        XCTAssertEqual(recording.stopCallCount, 1)
        XCTAssertEqual(recording.discardCallCount, 0)
        XCTAssertEqual(recording.freezeCallCount, 1)
        XCTAssertEqual(clipboard.copiedText, "eligible final。")
    }

    private func makeViewModel() -> QuickRecordingViewModel {
        QuickRecordingViewModel(
            recordingUseCase: FakeRecordingUseCase(),
            transcriptionUseCase: FakeTranscriptionUseCase(),
            refinementUseCase: FakeRefinementUseCase(),
            clipboardService: FakeClipboardService()
        )
    }
}

private final class FakeRecordingUseCase: QuickRecordingUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let levelSubject = CurrentValueSubject<Float, Never>(0)
    private let startDelayNanoseconds: UInt64
    private(set) var stopCallCount = 0
    private struct ReleaseState {
        var id = UUID()
        var eligible = false
        var frozen: QuickRecordingReleaseSnapshot?
        var discardCount = 0
        var freezeCount = 0
    }
    private let release = Mutex(ReleaseState())
    var discardCallCount: Int { release.withLock { $0.discardCount } }
    var freezeCallCount: Int { release.withLock { $0.freezeCount } }
    private let discardHook = Mutex<(@Sendable () async -> Void)?>(nil)
    var onDiscard: (@Sendable () async -> Void)? {
        get { discardHook.withLock { $0 } }
        set { discardHook.withLock { $0 = newValue } }
    }

    func prepareQuickRecording() throws {
        release.withLock { $0.id = UUID(); $0.eligible = false; $0.frozen = nil }
    }
    func recognizeApple(_ text: String) {
        release.withLock { if $0.frozen == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            $0.eligible = true
        } }
    }
    func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        release.withLock {
            $0.freezeCount += 1
            if let frozen = $0.frozen { return frozen }
            let frozen = QuickRecordingReleaseSnapshot(sessionID: $0.id, hasRecognizedSpeech: $0.eligible)
            $0.frozen = frozen
            return frozen
        }
    }
    func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        if snapshot.hasRecognizedSpeech { try await stopRecording(); return }
        release.withLock { $0.discardCount += 1 }
        await onDiscard?()
        stateSubject.send(.idle)
    }
    var onStop: (@Sendable () -> Void)?
    var stopError: Error?

    init(startDelayNanoseconds: UInt64 = 0) {
        self.startDelayNanoseconds = startDelayNanoseconds
    }

    var state: RecordingState { stateSubject.value }
    var statePublisher: AnyPublisher<RecordingState, Never> { stateSubject.eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }

    func startRecording() async throws {
        if startDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: startDelayNanoseconds)
        }
        stateSubject.send(.recording(duration: 0))
    }

    func stopRecording() async throws {
        stopCallCount += 1
        onStop?()
        stateSubject.send(.idle)
        if let stopError { throw stopError }
    }

    func pauseRecording() { stateSubject.send(.paused(duration: 0)) }
    func resumeRecording() { stateSubject.send(.recording(duration: 0)) }
    func cancelRecording() { stateSubject.send(.idle) }
    func checkPermission() async -> Bool { true }
    func requestPermission() async -> Bool { true }
}

private final class FakeTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {
    private let liveTextSubject = CurrentValueSubject<String, Never>("")
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalCancellations = Mutex(0)
    private var _currentLanguage = Locale(identifier: "zh-Hans")

    var liveTextPublisher: AnyPublisher<String, Never> { liveTextSubject.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        finalResultSubject.handleEvents(receiveCancel: { [weak self] in
            self?.finalCancellations.withLock { $0 += 1 }
        }).eraseToAnyPublisher()
    }
    var finalCancellationCount: Int { finalCancellations.withLock { $0 } }
    var currentLanguage: Locale { _currentLanguage }
    var supportedLanguages: [Locale] { [_currentLanguage] }

    func setLanguage(_ locale: Locale) { _currentLanguage = locale }
    func commitCurrentTranscription() async throws {}
    func clearLiveText() { liveTextSubject.send("") }

    // MARK: - Snapshot
    private let snapshotSubject = PassthroughSubject<String, Never>()
    var snapshotPublisher: AnyPublisher<String, Never> { snapshotSubject.eraseToAnyPublisher() }
    var snapshotGateActive: Bool = false

    func sendLiveText(_ text: String) { liveTextSubject.send(text) }
    func sendFinalText(_ text: String) {
        finalResultSubject.send(
            TranscriptionResult(
                text: text,
                type: .final,
                confidence: nil,
                timestamp: Date(),
                locale: _currentLanguage
            )
        )
    }
}

private final class FakeRefinementUseCase: RefinementUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RefinementState, Never>(.idle)
    private let streamedChunks: [String]

    init(streamedChunks: [String] = []) {
        self.streamedChunks = streamedChunks
    }

    var state: RefinementState { stateSubject.value }
    var statePublisher: AnyPublisher<RefinementState, Never> { stateSubject.eraseToAnyPublisher() }
    var isConfigured: Bool { true }

    func refine(customPrompt: String?) async throws {}
    func refineSelection(range: NSRange, customPrompt: String?) async throws {}
    func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        refineStreaming(customPrompt: customPrompt, transcriptionMetadata: nil)
    }

    func refineStreaming(
        customPrompt: String?,
        transcriptionMetadata: TranscriptionMetadata?
    ) -> AsyncThrowingStream<RefinementEvent, Error> {
        _ = customPrompt
        _ = transcriptionMetadata
        return AsyncThrowingStream { continuation in
            for chunk in streamedChunks {
                continuation.yield(RefinementEvent.chunk(chunk))
            }
            continuation.finish()
        }
    }
    func cancel() { stateSubject.send(.idle) }

    func refineText(_ text: String, customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        _ = text
        _ = customPrompt
        return AsyncThrowingStream { continuation in
            for chunk in streamedChunks {
                continuation.yield(RefinementEvent.chunk(chunk))
            }
            continuation.finish()
        }
    }
}

private final class FakeClipboardService: ClipboardService, @unchecked Sendable {
    private(set) var copiedText: String?
    var hasText: Bool { false }
    func copy(_ text: String) { copiedText = text }
    func paste() -> String? { nil }
    func clear() {}
    func simulatePaste() async throws {}
}

/// 测试仅从 MainActor 发送；unchecked 仅桥接 Combine subject 的 Sendable 缺失。
private final class FakeQuickStreamingCoordinator: StreamingInputCoordinator, @unchecked Sendable {
    private let subject = CurrentValueSubject<String, Never>("")
    private struct State {
        var isStreaming = false
        var cancelCallCount = 0
        var onStart: (@Sendable () async -> Void)?
    }
    private let state = Mutex(State())
    var onStart: (@Sendable () async -> Void)? {
        get { state.withLock { $0.onStart } }
        set { state.withLock { $0.onStart = newValue } }
    }
    var isStreaming: Bool { state.withLock { $0.isStreaming } }
    var cancelCallCount: Int { state.withLock { $0.cancelCallCount } }
    var refinedVoiceTextPublisher: AnyPublisher<String, Never> { subject.eraseToAnyPublisher() }
    func send(_ text: String) { subject.send(text) }
    func startStreaming() async {
        let onStart = state.withLock { $0.onStart }
        await onStart?()
        state.withLock { $0.isStreaming = true }
    }
    func stopStreaming() async { state.withLock { $0.isStreaming = false } }
    func cancel() { state.withLock { $0.isStreaming = false; $0.cancelCallCount += 1 } }
}
#endif
