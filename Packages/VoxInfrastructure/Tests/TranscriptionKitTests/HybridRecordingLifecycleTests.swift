import Foundation
import AVFoundation
import Synchronization
import XCTest
@testable import TranscriptionKit

final class HybridRecordingLifecycleTests: XCTestCase {
    func testQuickAppleLatchAcceptsStartingAndRemainsTrueAfterWhitespace() throws {
        let lifecycle = HybridRecordingLifecycle()
        try lifecycle.prepareQuickRecording()
        let id = try lifecycle.begin(locale: .current)
        XCTAssertTrue(lifecycle.receiveApple(" \n", id: id))
        XCTAssertTrue(lifecycle.receiveApple("synthetic apple", id: id))
        try lifecycle.didStart(id)
        XCTAssertTrue(lifecycle.receiveCloud("synthetic cloud", id: id))
        XCTAssertFalse(lifecycle.receiveApple("\t", id: id))
        XCTAssertTrue(try lifecycle.freezeQuickRecordingRelease().hasRecognizedSpeech)
        lifecycle.complete(id)
    }

    func testQuickCloudAndUsableAudioDoNotSupplyAppleEligibility() throws {
        let lifecycle = HybridRecordingLifecycle()
        try lifecycle.prepareQuickRecording()
        let id = try lifecycle.begin(locale: .current)
        let config = try AzureRealtimeTranscriptionConfig(endpoint: URL(string: "https://example.invalid")!,
                                                          apiKey: "fixture", deployment: "live")
        let pipeline = RealtimeAudioPipeline(session: DefaultRealtimeTranscriptionSession(config: config, onPartial: { _ in }))
        try lifecycle.attach(pipeline, id: id)
        pipeline.append(audio(frames: 4800))
        try lifecycle.didStart(id)
        XCTAssertTrue(lifecycle.receiveCloud("synthetic cloud", id: id))
        XCTAssertTrue(pipeline.hasMinimumAudio)
        let frozen = try lifecycle.freezeQuickRecordingRelease()
        XCTAssertFalse(frozen.hasRecognizedSpeech)
        XCTAssertFalse(lifecycle.receiveApple("late synthetic apple", id: id))
        XCTAssertNil(lifecycle.restoreApplePreview(id))
        XCTAssertEqual(try lifecycle.freezeQuickRecordingRelease(), frozen)
        let forgedUpgrade = QuickRecordingReleaseSnapshot(sessionID: id, hasRecognizedSpeech: true)
        guard case .none = lifecycle.claimQuickRelease(forgedUpgrade) else { return XCTFail("Must not upgrade") }
        guard case .discard = lifecycle.claimQuickRelease(frozen) else { return XCTFail("Expected discard") }
        pipeline.cancel()
        lifecycle.complete(id)
    }

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
        pipeline.append(audio(frames: 4800))
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

    func testImmediateReleaseWithoutUsableAudioSkipsRealtimeAndBatch() async throws {
        for frames: UInt32 in [0, 4799] {
            let lifecycle = HybridRecordingLifecycle()
            let id = try lifecycle.begin(locale: .current)
            let config = try AzureRealtimeTranscriptionConfig(endpoint: URL(string: "https://example.invalid")!,
                                                              apiKey: "fixture", deployment: "live")
            let socket = FakeRealtimeTransport(acknowledge: false)
            let session = DefaultRealtimeTranscriptionSession(config: config, transport: socket,
                                                             timeout: .milliseconds(20), onPartial: { _ in })
            let pipeline = RealtimeAudioPipeline(session: session)
            try lifecycle.attach(pipeline, id: id)
            if frames > 0 { pipeline.append(audio(frames: frames)) }
            try lifecycle.didStart(id)
            guard case .finish(let snapshot) = lifecycle.requestStop() else { return XCTFail("Expected stop") }
            XCTAssertFalse(snapshot.shouldFinalize, "A quick tap must not finalize unusable audio")
            var realtimeCalls = 0
            var batchCalls = 0
            if snapshot.shouldFinalize {
                _ = try await RealtimeASRFinalizer.resolve(realtime: {
                    realtimeCalls += 1
                    return try await pipeline.finish()
                }, fallback: { batchCalls += 1; return "synthetic batch" })
            } else {
                pipeline.cancel()
            }
            XCTAssertEqual(realtimeCalls, 0)
            XCTAssertEqual(batchCalls, 0)
            lifecycle.complete(id)
            let next = try lifecycle.begin(locale: .current)
            lifecycle.complete(next)
        }
    }

    func testUsableAudioWithoutPartialIsMeasuredAcrossBuffersAndSampleRates() throws {
        for rate in [24_000.0, 44_100.0, 48_000.0] {
            let lifecycle = HybridRecordingLifecycle()
            let id = try lifecycle.begin(locale: .current)
            let config = try AzureRealtimeTranscriptionConfig(endpoint: URL(string: "https://example.invalid")!,
                                                              apiKey: "fixture", deployment: "live")
            let pipeline = RealtimeAudioPipeline(session: DefaultRealtimeTranscriptionSession(config: config, onPartial: { _ in }))
            try lifecycle.attach(pipeline, id: id)
            for _ in 0..<2 { pipeline.append(audio(frames: UInt32(rate / 20), rate: rate)) }
            try lifecycle.didStart(id)
            guard case .finish(let snapshot) = lifecycle.requestStop() else { return XCTFail("Expected stop") }
            XCTAssertTrue(snapshot.shouldFinalize)
            pipeline.cancel()
            lifecycle.complete(id)
        }
    }

    private func audio(frames: UInt32, rate: Double = 48_000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = 0.1 }
        return buffer
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
