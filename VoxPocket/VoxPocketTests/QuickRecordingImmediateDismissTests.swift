#if os(macOS)
import Foundation
import PlatformUI
import Testing
import UIShared
@testable import VoxPocket

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct QuickRecordingImmediateDismissTests {
    @Test(arguments: [false, true])
    func recognitionBoundaryThenHiddenPipelinePreservesPasteSaveAndSessionIsolation(saveFails: Bool) async throws {
        let stop = QuickRecordStartGate()
        let fixture = ImmediateDismissFixture(stopGate: stop)
        defer { fixture.remove() }
        fixture.saveFails = saveFails
        await fixture.launch()
        await fixture.hotkeys.press()
        let model = try #require(fixture.model)
        let oldComplete = model.onComplete, oldNoResult = model.onNoResult
        let oldRecognitionEnded = model.onRecognitionEnded
        let release = Task { await fixture.hotkeys.release() }
        try await waitForDismissBoundary { fixture.recording.stopCallCount == 1 }
        fixture.expectVisibleAndBusy()
        #expect(fixture.events.map(\.0) == ["quick_record.fn_released"])
        await fixture.hotkeys.release()
        await fixture.hotkeys.press()
        #expect(fixture.recording.startCallCount == 1)
        #expect(fixture.events.count == 1)
        await stop.release()
        await release.value
        try await waitForDismissBoundary { fixture.refinement.isWaiting }
        fixture.expectHiddenAndBusy()
        assertQuickRecordTimingEvents(fixture)
        fixture.refinement.finish()
        try await waitForDismissBoundary { fixture.clipboard.pasteCount == 1 }
        fixture.expectHiddenAndBusy()
        await fixture.clipboard.gate.release()
        try await waitForDismissBoundary { fixture.saved.count == 1 }
        fixture.expectHiddenAndBusy()
        oldComplete?("duplicate"); oldNoResult?()
        await fixture.saveGate.release()
        try await waitForDismissBoundary { fixture.source == nil }
        fixture.expectClean()
        #expect(fixture.clipboard.copied == ["synthetic refined。"])
        #expect(fixture.clipboard.pasteCount == 1)
        #expect(fixture.saved.count == 1)
        #expect(fixture.saved.first?.0 == "synthetic raw")
        #expect(fixture.saved.first?.1 == "synthetic refined。")
        await assertStaleCallbacksPreserveNextSession(fixture, model: model,
                                                    complete: oldComplete, noResult: oldNoResult,
                                                    recognitionEnded: oldRecognitionEnded)
    }

    private func assertStaleCallbacksPreserveNextSession(
        _ fixture: ImmediateDismissFixture, model: QuickRecordingViewModel,
        complete: ((String) -> Void)?, noResult: (() -> Void)?, recognitionEnded: (() -> Void)?
    ) async {
        fixture.model = model
        model.recorderStatus = .idle
        await fixture.hotkeys.press()
        complete?("stale"); noResult?(); recognitionEnded?()
        #expect(fixture.visible)
        #expect(fixture.source == .quickRecording)
        #expect(fixture.closes == 1)
        #expect(fixture.ends == 1)
        #expect(fixture.saved.count == 1)
        await model.cancelFromPanel()
    }

    @Test(arguments: [false, true])
    func releaseDuringStartupHidesBeforeStartReturns(startFails: Bool) async throws {
        let startGate = QuickRecordStartGate()
        let fixture = ImmediateDismissFixture(startGate: startGate, startFails: startFails, hasResult: false)
        defer { fixture.remove() }
        await fixture.launch()
        let start = Task { await fixture.hotkeys.press() }
        try await waitForDismissBoundary { fixture.model?.isStartingRecording == true }
        await fixture.hotkeys.release()
        fixture.expectHiddenAndBusy()
        #expect(fixture.recording.stopCallCount == 0)
        assertQuickRecordTimingEvents(fixture)
        await startGate.release()
        await start.value
        fixture.expectClean()
        #expect(fixture.recording.stopCallCount == 0)
        #expect(fixture.recording.discardCallCount == 1)
        #expect(fixture.clipboard.pasteCount == 0)
        #expect(fixture.saved.isEmpty)
    }

    @Test(arguments: [false, true])
    func stopErrorOrNoResultHidesAndReleases(stopFails: Bool) async throws {
        let fixture = ImmediateDismissFixture(stopFails: stopFails, hasResult: false)
        defer { fixture.remove() }
        await fixture.launch()
        await fixture.hotkeys.press()
        await fixture.hotkeys.release()
        fixture.expectClean()
        assertQuickRecordTimingEvents(fixture)
        #expect(fixture.recording.stopCallCount == (stopFails ? 1 : 0))
        #expect(fixture.recording.discardCallCount == (stopFails ? 0 : 1))
        #expect(fixture.saved.isEmpty)
        #expect(fixture.clipboard.pasteCount == 0)
    }

    @Test func emptyAppleReleaseRetainsOwnershipUntilDiscardAndSuppressesLateOutput() async throws {
        let discard = QuickRecordStartGate()
        let fixture = ImmediateDismissFixture(stopGate: discard, hasResult: false)
        defer { fixture.remove() }
        await fixture.launch()
        await fixture.hotkeys.press()
        let release = Task { await fixture.hotkeys.release() }
        try await waitForDismissBoundary { fixture.recording.discardCallCount == 1 }
        fixture.expectHiddenAndBusy()
        assertQuickRecordTimingEvents(fixture)
        fixture.recording.recognizeApple("late Apple")
        fixture.transcription.sendFinalText("late cloud final")
        await fixture.hotkeys.release()
        await fixture.hotkeys.press()
        #expect(fixture.recording.startCallCount == 1)
        #expect(fixture.events.count == 2)
        #expect(!fixture.refinement.isWaiting)
        #expect(fixture.saved.isEmpty)
        await discard.release()
        await release.value
        fixture.expectClean()
        #expect(fixture.recording.stopCallCount == 0)
        #expect(fixture.recording.discardCallCount == 1)
        #expect(!fixture.refinement.isWaiting)
        #expect(fixture.clipboard.copied.isEmpty)
        #expect(fixture.clipboard.pasteCount == 0)
        #expect(fixture.saved.isEmpty)
    }

    @Test func startupErrorWithoutReleaseAndMissingModelCleanImmediately() async {
        let failed = ImmediateDismissFixture(startFails: true)
        defer { failed.remove() }
        await failed.launch()
        await failed.hotkeys.press()
        failed.expectClean()
        #expect(failed.events.isEmpty)
        let missing = ImmediateDismissFixture()
        defer { missing.remove() }
        missing.model = nil
        await missing.launch()
        await missing.hotkeys.press()
        await missing.hotkeys.release()
        missing.expectClean()
        #expect(missing.events.isEmpty)
    }

    @Test func missingModelAtReleaseCleansWithoutTimingEvents() async {
        let fixture = ImmediateDismissFixture(hasResult: false)
        defer { fixture.remove() }
        await fixture.launch()
        await fixture.hotkeys.press()
        let model = fixture.model
        fixture.model = nil
        await fixture.hotkeys.release()
        fixture.expectClean()
        #expect(fixture.events.isEmpty)
        withExtendedLifetime(model) {}
    }

    @Test func rejectedOtherSourceDoesNotShowOrEmit() async {
        let fixture = ImmediateDismissFixture()
        defer { fixture.remove() }
        await fixture.launch()
        fixture.source = .fullPanel
        await fixture.hotkeys.press()
        await fixture.hotkeys.release()
        #expect(!fixture.visible)
        #expect(fixture.source == .fullPanel)
        #expect(fixture.events.isEmpty)
        #expect(fixture.ends == 0)
    }

}
#endif
