#if os(macOS)
import Combine
import Foundation
import XCTest
@testable import PlatformUI

@MainActor
final class QuickRecordingRecognitionBoundaryTests: XCTestCase {
    func testFinalBeforeStartupReturnsSurvivesReleaseAndHidesBeforeStreamingStop() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let streaming = FakeQuickStreamingCoordinator()
        let clipboard = FakeClipboardService()
        let startupEntered = expectation(description: "startup suspended after early final")
        let stopEntered = expectation(description: "downstream streaming stop")
        let startupGate = AsyncStream<Void>.makeStream()
        let stopGate = AsyncStream<Void>.makeStream()
        recording.onStart = {
            recording.recognizeApple("synthetic Apple")
            transcription.sendFinalText("early provider final")
            startupEntered.fulfill()
            for await _ in startupGate.stream { break }
        }
        streaming.onStop = { stopEntered.fulfill(); for await _ in stopGate.stream { break } }
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard,
                                           streamingCoordinator: streaming)
        var boundaries = 0
        model.onRecognitionEnded = { boundaries += 1 }
        let start = Task { await model.startRecording() }
        await fulfillment(of: [startupEntered], timeout: 1)
        XCTAssertTrue(model.prepareQuickRecordingRelease())
        await model.stopRecording()
        XCTAssertEqual(boundaries, 0)
        XCTAssertEqual(recording.freezeCallCount, 1)
        XCTAssertEqual(recording.stopCallCount, 0)
        startupGate.continuation.finish()
        await fulfillment(of: [stopEntered], timeout: 1)
        XCTAssertEqual(model.rawTranscription, "early provider final")
        XCTAssertEqual(boundaries, 1)
        XCTAssertNil(clipboard.copiedText)
        stopGate.continuation.finish()
        await start.value
        XCTAssertEqual(clipboard.copiedText, "early provider final。")
        XCTAssertEqual(recording.stopCallCount, 1)
        XCTAssertEqual(recording.freezeCallCount, 1)
        await model.stopRecording()
        XCTAssertEqual(boundaries, 1)
    }

    func testReleaseWaitsForFinalThenNotifiesBeforeDownstreamStreamingWait() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let streaming = FakeQuickStreamingCoordinator()
        let clipboard = FakeClipboardService()
        let stopEntered = expectation(description: "streaming stop entered")
        let stopGate = AsyncStream<Void>.makeStream()
        streaming.onStop = { stopEntered.fulfill(); for await _ in stopGate.stream { break } }
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard,
                                           streamingCoordinator: streaming)
        var boundaries = 0
        model.onRecognitionEnded = { boundaries += 1 }
        await model.startRecording()
        recording.recognizeApple("Apple qualifies only")
        XCTAssertTrue(model.prepareQuickRecordingRelease())
        let release = Task { await model.stopRecording() }
        await waitUntil { recording.stopCallCount == 1 }
        XCTAssertEqual(boundaries, 0)
        XCTAssertNil(clipboard.copiedText)
        transcription.sendFinalText("selected provider final")
        await fulfillment(of: [stopEntered], timeout: 1)
        XCTAssertEqual(boundaries, 1)
        XCTAssertEqual(model.rawTranscription, "selected provider final")
        XCTAssertNil(clipboard.copiedText)
        stopGate.continuation.finish()
        await release.value
        XCTAssertEqual(clipboard.copiedText, "selected provider final。")
        XCTAssertEqual(recording.discardCallCount, 0)
    }

    func testCancellationDuringFinalWaitNotifiesAndCannotProduceOutput() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let clipboard = FakeClipboardService()
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard)
        var boundaries = 0
        model.onRecognitionEnded = { boundaries += 1 }
        await model.startRecording()
        recording.recognizeApple("synthetic Apple")
        let release = Task { await model.stopRecording() }
        await waitUntil { recording.stopCallCount == 1 }
        release.cancel()
        await release.value
        XCTAssertEqual(boundaries, 1)
        XCTAssertEqual(transcription.finalCancellationCount, 1)
        transcription.sendFinalText("late final")
        XCTAssertNil(clipboard.copiedText)
        XCTAssertTrue(model.rawTranscription.isEmpty)
    }

    func testDiscardCancelsEarlyCaptureAndNextSessionUsesFreshFinal() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let clipboard = FakeClipboardService()
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard,
                                           streamingCoordinator: FakeQuickStreamingCoordinator())
        await model.startRecording()
        transcription.sendFinalText("cloud alone cannot qualify")
        XCTAssertFalse(model.prepareQuickRecordingRelease())
        recording.recognizeApple("late Apple")
        await model.stopRecording()
        XCTAssertEqual(recording.discardCallCount, 1)
        XCTAssertNil(clipboard.copiedText)
        await model.startRecording()
        recording.recognizeApple("fresh Apple")
        transcription.sendFinalText("fresh final")
        await model.stopRecording()
        XCTAssertEqual(model.rawTranscription, "fresh final")
        XCTAssertEqual(clipboard.copiedText, "fresh final。")
        XCTAssertEqual(recording.stopCallCount, 1)
        XCTAssertEqual(recording.freezeCallCount, 2)
    }

    func testStopFailureEndsRecognitionOnceAndCancelsCapture() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let clipboard = FakeClipboardService()
        recording.stopError = CancellationError()
        let model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                           refinementUseCase: FakeRefinementUseCase(), clipboardService: clipboard)
        var boundaries = 0
        model.onRecognitionEnded = { boundaries += 1 }
        await model.startRecording()
        recording.recognizeApple("synthetic Apple")
        await model.stopRecording()
        await model.stopRecording()
        XCTAssertEqual(boundaries, 1)
        XCTAssertEqual(transcription.finalCancellationCount, 1)
        XCTAssertNil(clipboard.copiedText)
    }

    func testWatchdogHidesOnlyAndIncludesRecognitionWaitInDuration() async {
        let lifecycle = QuickRecordingReleaseLifecycle(timeout: .milliseconds(20))
        let hidden = expectation(description: "watchdog hid")
        var dismissals = 0
        var milliseconds: Double?
        lifecycle.release()
        lifecycle.armWatchdog {
            milliseconds = lifecycle.hide { dismissals += 1; return true }
            hidden.fulfill()
        }
        XCTAssertTrue(lifecycle.isReleased)
        XCTAssertEqual(dismissals, 0)
        await fulfillment(of: [hidden], timeout: 1)
        XCTAssertEqual(dismissals, 1)
        XCTAssertGreaterThanOrEqual(milliseconds ?? -1, 20)
        XCTAssertNil(lifecycle.hide { dismissals += 1; return true })
        XCTAssertEqual(dismissals, 1)
    }

    func testNormalHideCancelsWatchdogAndDoesNotDelayForBudget() async {
        let lifecycle = QuickRecordingReleaseLifecycle(timeout: .milliseconds(10))
        let deadline = expectation(description: "cancelled watchdog")
        deadline.isInverted = true
        lifecycle.release()
        lifecycle.armWatchdog { deadline.fulfill() }
        XCTAssertNotNil(lifecycle.hide { true })
        lifecycle.release()
        lifecycle.armWatchdog { deadline.fulfill() }
        await fulfillment(of: [deadline], timeout: 0.04)
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<10_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Controlled boundary not reached")
    }
}
#endif
