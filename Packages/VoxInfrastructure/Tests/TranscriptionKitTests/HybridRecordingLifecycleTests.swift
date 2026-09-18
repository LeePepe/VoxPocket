import Foundation
import Synchronization
import XCTest
@testable import TranscriptionKit

final class HybridRecordingLifecycleTests: XCTestCase {
    func testStopDuringPermissionWaitPreventsStartAndWaitsForCleanup() async throws {
        let lifecycle = HybridRecordingLifecycle()
        let id = try lifecycle.begin(locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(lifecycle.isStarting(id))
        guard case .cancelStart(let cancelled) = lifecycle.requestStop() else { return XCTFail("Expected startup cancel") }
        XCTAssertEqual(cancelled.id, id)
        XCTAssertFalse(lifecycle.isStarting(id))
        XCTAssertThrowsError(try lifecycle.didStart(id))
        XCTAssertThrowsError(try lifecycle.begin(locale: .current))
        let done = Mutex(false)
        let stopped = Task { await lifecycle.waitForCleanup(id); done.withLock { $0 = true } }
        await Task.yield()
        XCTAssertFalse(done.withLock { $0 })
        lifecycle.complete(id)
        await stopped.value
        XCTAssertTrue(done.withLock { $0 })
        let next = try lifecycle.begin(locale: .current)
        XCTAssertNotEqual(next, id)
        XCTAssertFalse(lifecycle.receiveCloud("old synthetic text", id: id))
        lifecycle.complete(next)
    }

    func testStopAfterCleanupDoesNotLoseWakeup() async throws {
        let lifecycle = HybridRecordingLifecycle()
        let id = try lifecycle.begin(locale: .current)
        _ = lifecycle.requestStop()
        lifecycle.complete(id)
        await lifecycle.waitForCleanup(id)
        XCTAssertFalse(lifecycle.isRecording)
    }

    func testRealtimeWithoutAnyPartialStillFinalizesAndFallsBackOnce() async throws {
        let lifecycle = HybridRecordingLifecycle()
        let id = try lifecycle.begin(locale: .current)
        let config = try AzureRealtimeTranscriptionConfig(endpoint: URL(string: "https://example.invalid")!,
                                                          apiKey: "fixture", deployment: "live")
        let socket = FakeRealtimeTransport(acknowledge: false)
        let session = DefaultRealtimeTranscriptionSession(config: config, transport: socket,
                                                         timeout: .milliseconds(20), onPartial: { _ in })
        let pipeline = RealtimeAudioPipeline(session: session)
        try lifecycle.attach(pipeline, id: id)
        pipeline.start(language: "zh")
        try lifecycle.didStart(id)
        guard case .finish(let snapshot) = lifecycle.requestStop() else { return XCTFail("Expected finalization") }
        XCTAssertTrue(snapshot.appleText.isEmpty)
        XCTAssertTrue(snapshot.cloudText.isEmpty)
        XCTAssertTrue(snapshot.shouldFinalize)
        var fallbackCount = 0
        let text = try await RealtimeASRFinalizer.resolve(realtime: { try await pipeline.finish() }, fallback: {
            fallbackCount += 1; return "synthetic batch result"
        })
        XCTAssertEqual(text, "synthetic batch result")
        XCTAssertEqual(fallbackCount, 1)
        guard case .none = lifecycle.requestStop() else { return XCTFail("Must not finalize twice") }
        lifecycle.complete(id)
    }

    func testLegacySilenceStillSkipsBatch() throws {
        let lifecycle = HybridRecordingLifecycle()
        let id = try lifecycle.begin(locale: .current)
        try lifecycle.didStart(id)
        guard case .finish(let snapshot) = lifecycle.requestStop() else { return XCTFail("Expected stop") }
        XCTAssertFalse(snapshot.shouldFinalize)
        lifecycle.complete(id)
    }

    func testCloudFailureRestoresApplePreviewAndRejectsOldFailure() throws {
        let lifecycle = HybridRecordingLifecycle()
        let id = try lifecycle.begin(locale: .current)
        try lifecycle.didStart(id)
        XCTAssertTrue(lifecycle.receiveCloud("cloud partial", id: id))
        XCTAssertFalse(lifecycle.receiveApple("newer apple partial", id: id))
        XCTAssertEqual(lifecycle.restoreApplePreview(id), "newer apple partial")
        XCTAssertTrue(lifecycle.receiveApple("still recording", id: id))
        lifecycle.complete(id)
        let next = try lifecycle.begin(locale: .current)
        try lifecycle.didStart(next)
        XCTAssertNil(lifecycle.restoreApplePreview(id))
        lifecycle.complete(next)
    }

    func testCancelledCaptureDoesNotAskForHardwarePermission() async {
        let recorder = MicrophoneRecorder()
        do { try await recorder.startIfAllowed(shouldStart: { false }); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(recorder.stop())
    }
}
