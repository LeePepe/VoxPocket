import Combine
import Foundation
import Synchronization
import XCTest
@testable import TranscriptionKit

final class QuickRecordingReleaseControlTests: XCTestCase {
    func testCloudPreviewDoesNotAllowQuickFinalizationButNormalStopStillFinalizes() async throws {
        for provider in [QuickRecordingTestProvider.batch, .realtime] {
            let probe = QuickRecordingEffectProbe(realtime: provider == .realtime)
            let source = try XCTUnwrap(provider.make(probe) as? HybridWhisperTranscriber)
            try source.prepareQuickRecording()
            try await source.start(language: .current)
            source.receiveCloudText("synthetic cloud", id: probe.sessionID, locale: .current)
            let frozen = try source.freezeQuickRecordingRelease()
            XCTAssertFalse(frozen.hasRecognizedSpeech)
            try await source.completeQuickRecordingRelease(frozen)
            XCTAssertEqual(probe.count("batch"), 0)
            XCTAssertEqual(probe.count("realtimeFinish"), 0)
            try await source.start(language: .current)
            source.receiveCloudText("synthetic ordinary cloud", id: probe.sessionID, locale: .current)
            await source.stop()
            XCTAssertEqual(probe.count(provider == .realtime ? "realtimeFinish" : "batch"), 1)
        }
    }

    func testOrdinaryAppleStopRetainsDelayedFinal() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = AppleSpeechTranscriber(effects: probe.effects)
        let seen = Mutex(0)
        let subscription = source.finalResultPublisher.sink(receiveCompletion: { _ in }, receiveValue: { _ in
            seen.withLock { $0 += 1 }
        })
        defer { subscription.cancel() }
        try await source.start(language: .current)
        await source.stop()
        probe.send("synthetic delayed final", type: .final)
        XCTAssertEqual(seen.withLock { $0 }, 1)
        XCTAssertEqual(probe.count("endApple"), 1)
        XCTAssertEqual(probe.count("cancelApple"), 0)
    }

    func testDiscardInvokesRealCleanupAndNoFinalizationForEveryQuickProvider() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let probe = QuickRecordingEffectProbe(realtime: provider == .realtime)
            let source = provider.make(probe)
            let merger = QuickRecordingCountingMerger()
            (source as? HybridWhisperTranscriber)?.merger = merger
            let finals = Mutex(0)
            let subscription = source.finalResultPublisher.sink(receiveCompletion: { _ in }, receiveValue: { _ in
                finals.withLock { $0 += 1 }
            })
            try source.prepareQuickRecording()
            try await source.start(language: .current)
            probe.send(" \n\t")
            let frozen = try source.freezeQuickRecordingRelease()
            XCTAssertFalse(frozen.hasRecognizedSpeech)
            probe.send("late synthetic speech", type: .final)
            try await source.completeQuickRecordingRelease(frozen)
            try await source.completeQuickRecordingRelease(frozen)
            probe.send("late synthetic final", type: .final)
            XCTAssertEqual(probe.count("stop"), 1)
            XCTAssertEqual(probe.count("cancelApple"), 1)
            XCTAssertEqual(probe.count("removeAudio"), 1)
            XCTAssertEqual(probe.count("cancelRealtime"), provider == .apple ? 0 : 1)
            for event in ["endApple", "realtimeFinish", "commit", "batch", "fallback"] {
                XCTAssertEqual(probe.count(event), 0, "Discard invoked \(event)")
            }
            XCTAssertEqual(merger.calls.withLock { $0 }, 0)
            XCTAssertEqual(finals.withLock { $0 }, 0)
            XCTAssertFalse(source.isTranscribing)
            subscription.cancel()
        }
    }

    func testAppleEvidenceDuringStartupIsStickyAndAllowsFinalization() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            for type in [TranscriptionResultType.partial, .final] {
                let probe = QuickRecordingEffectProbe(earlyResult: .init(text: "synthetic apple", type: type),
                                                      realtime: provider == .realtime)
                let source = provider.make(probe)
                try source.prepareQuickRecording()
                try await source.start(language: .current)
                probe.send(" \n")
                let frozen = try source.freezeQuickRecordingRelease()
                XCTAssertTrue(frozen.hasRecognizedSpeech)
                try await source.completeQuickRecordingRelease(frozen)
                XCTAssertEqual(probe.count("stop"), 1)
                XCTAssertEqual(probe.count("endApple"), 1)
                XCTAssertEqual(probe.count(provider == .realtime ? "realtimeFinish" : "batch"),
                               provider == .apple ? 0 : 1)
            }
        }
    }

    func testReleaseBeforeAsyncStartDoesNotStartCapture() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let probe = QuickRecordingEffectProbe()
            let source = provider.make(probe)
            try source.prepareQuickRecording()
            let frozen = try source.freezeQuickRecordingRelease()
            do { try await source.start(language: .current); XCTFail("Released startup must cancel") }
            catch { XCTAssertTrue(error is CancellationError) }
            try await source.completeQuickRecordingRelease(frozen)
            XCTAssertEqual(probe.count("start"), 0)
            try source.prepareQuickRecording()
            try await source.start(language: .current)
            let next = try source.freezeQuickRecordingRelease()
            XCTAssertNotEqual(next.sessionID, frozen.sessionID)
            try await source.completeQuickRecordingRelease(next)
        }
    }

    func testDiscardDuringStartupWaitsForCleanupAndRejectsLateSpeech() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let startingGate = QuickRecordingEffectGate()
            let cleanupGate = QuickRecordingEffectGate()
            let probe = QuickRecordingEffectProbe(startGate: startingGate, cleanupGate: cleanupGate)
            let source = provider.make(probe)
            try source.prepareQuickRecording()
            let starting = Task { try await source.start(language: .current) }
            await startingGate.entered()
            let frozen = try source.freezeQuickRecordingRelease()
            probe.send("late synthetic apple")
            let done = Mutex(false)
            let completing = Task {
                try await source.completeQuickRecordingRelease(frozen)
                done.withLock { $0 = true }
            }
            await startingGate.release()
            await cleanupGate.entered()
            XCTAssertFalse(done.withLock { $0 })
            XCTAssertThrowsError(try source.prepareQuickRecording())
            await cleanupGate.release()
            _ = await starting.result
            try await completing.value
            XCTAssertEqual(probe.count("stop"), 1)
            XCTAssertEqual(probe.count("removeAudio"), 1)
            XCTAssertEqual(probe.count("batch"), 0)
            XCTAssertEqual(probe.count("endApple"), 0)
        }
    }

    func testOldCallbacksAndTokensCannotAffectNextRecording() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let probe = QuickRecordingEffectProbe()
            let source = provider.make(probe)
            try source.prepareQuickRecording()
            try await source.start(language: .current)
            probe.send("first synthetic apple")
            let old = try source.freezeQuickRecordingRelease()
            try await source.completeQuickRecordingRelease(old)
            try source.prepareQuickRecording()
            try await source.start(language: .current)
            probe.send("stale synthetic apple", type: .final, index: 0)
            try await source.completeQuickRecordingRelease(old)
            XCTAssertTrue(source.isTranscribing)
            let next = try source.freezeQuickRecordingRelease()
            XCTAssertFalse(next.hasRecognizedSpeech)
            try await source.completeQuickRecordingRelease(next)
            XCTAssertEqual(probe.count("stop"), 2)
        }
    }

    func testExplicitCancellationCanDowngradeEligibleFrozenSession() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let probe = QuickRecordingEffectProbe()
            let source = provider.make(probe)
            try source.prepareQuickRecording()
            try await source.start(language: .current)
            probe.send("synthetic apple")
            let frozen = try source.freezeQuickRecordingRelease()
            XCTAssertTrue(frozen.hasRecognizedSpeech)
            try await source.completeQuickRecordingRelease(.init(sessionID: frozen.sessionID, hasRecognizedSpeech: false))
            XCTAssertEqual(probe.count("cancelApple"), 1)
            XCTAssertEqual(probe.count("endApple"), 0)
            XCTAssertEqual(probe.count("batch"), 0)
        }
    }

    func testProductionRealtimeCancellationAwaitsTransportCloseBeforeReturning() async throws {
        let transport = QuickRecordingClosingTransport()
        let config = try AzureRealtimeTranscriptionConfig(endpoint: URL(string: "https://example.invalid")!,
                                                          apiKey: "fixture", deployment: "live")
        let session = DefaultRealtimeTranscriptionSession(config: config, transport: transport, onPartial: { _ in })
        let pipeline = RealtimeAudioPipeline(session: session)
        let done = Mutex(false)
        let cancellation = Task {
            await cancelQuickRecordingRealtime(pipeline, session: session)
            done.withLock { $0 = true }
        }
        await transport.closing.entered()
        XCTAssertFalse(done.withLock { $0 })
        await transport.closing.release()
        await cancellation.value
        XCTAssertTrue(done.withLock { $0 })
        let closes = await transport.closes
        XCTAssertEqual(closes, 1)
    }

    func testCleanupFailureStillReleasesSessionWithoutPublishingFinal() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let probe = QuickRecordingEffectProbe(cleanupFails: true)
            let source = provider.make(probe)
            try source.prepareQuickRecording()
            try await source.start(language: .current)
            let frozen = try source.freezeQuickRecordingRelease()
            do { try await source.completeQuickRecordingRelease(frozen); XCTFail("Expected cleanup failure") }
            catch { XCTAssertTrue(error is QuickRecordingReleaseError) }
            XCTAssertFalse(source.isTranscribing)
            XCTAssertEqual(probe.count("batch"), 0)
            try source.prepareQuickRecording()
        }
    }
}
