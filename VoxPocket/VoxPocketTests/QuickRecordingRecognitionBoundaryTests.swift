#if os(macOS)
import Foundation
import PlatformUI
import Testing
import UIShared

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct QuickRecordingRecognitionBoundaryTests {
    @Test func earlyFinalDuringStartupIsRetainedUntilEligibleReleaseCompletes() async throws {
        let startGate = QuickRecordStartGate()
        let fixture = ImmediateDismissFixture(startGate: startGate, hasResult: false)
        defer { fixture.remove() }
        await fixture.launch()
        let start = Task { await fixture.hotkeys.press() }
        await startGate.waitUntilEntered()
        fixture.recording.recognizeApple("synthetic Apple evidence")
        fixture.transcription.sendFinalText("synthetic early final")

        await fixture.hotkeys.release()
        fixture.expectVisibleAndBusy()
        #expect(fixture.events.map(\.0) == ["quick_record.fn_released"])
        #expect(fixture.recording.stopCallCount == 0)
        await startGate.release()
        await start.value

        try await finishHiddenOutput(fixture, expectedRaw: "synthetic early final")
        #expect(fixture.recording.stopCallCount == 1)
        #expect(fixture.recording.discardCallCount == 0)
        assertQuickRecordTimingEvents(fixture)
    }

    @Test func providerWatchdogHidesButDoesNotCancelEligibleBackgroundOutput() async throws {
        let stopGate = QuickRecordStartGate()
        let fixture = ImmediateDismissFixture(stopGate: stopGate)
        defer { fixture.remove() }
        await fixture.launch(recognitionTimeout: .milliseconds(100))
        await fixture.hotkeys.press()
        let release = Task { await fixture.hotkeys.release() }
        await stopGate.waitUntilEntered()

        await fixture.waitForVisualDismissal()
        fixture.expectHiddenAndBusy()
        #expect(fixture.recording.stopCallCount == 1)
        #expect(fixture.recording.discardCallCount == 0)
        #expect(!fixture.refinement.isWaiting)
        #expect(fixture.clipboard.copied.isEmpty)
        #expect(fixture.saved.isEmpty)
        await fixture.hotkeys.release()
        await fixture.hotkeys.press()
        #expect(fixture.recording.startCallCount == 1)
        assertQuickRecordTimingEvents(fixture)
        #expect((Double(fixture.events.last?.1["duration_ms"] ?? "") ?? -1) >= 100)

        await stopGate.release()
        await release.value
        try await finishHiddenOutput(fixture, expectedRaw: "synthetic raw")
        #expect(fixture.events.count == 2)
    }

    @Test func startupWatchdogIsArmedAtReleaseAndPreservesPendingOwnership() async throws {
        let startGate = QuickRecordStartGate()
        let fixture = ImmediateDismissFixture(startGate: startGate)
        defer { fixture.remove() }
        await fixture.launch(recognitionTimeout: .milliseconds(100))
        let start = Task { await fixture.hotkeys.press() }
        await startGate.waitUntilEntered()
        fixture.recording.recognizeApple("synthetic early Apple evidence")
        #expect(fixture.events.isEmpty)
        await fixture.hotkeys.release()
        await fixture.waitForVisualDismissal()

        fixture.expectHiddenAndBusy()
        #expect(fixture.recording.startCallCount == 1)
        #expect(fixture.recording.stopCallCount == 0)
        #expect(fixture.recording.discardCallCount == 0)
        #expect(!fixture.refinement.isWaiting)
        #expect(fixture.saved.isEmpty)
        await fixture.hotkeys.release()
        await fixture.hotkeys.press()
        #expect(fixture.recording.startCallCount == 1)
        assertQuickRecordTimingEvents(fixture)
        #expect((Double(fixture.events.last?.1["duration_ms"] ?? "") ?? -1) >= 100)

        await startGate.release()
        await start.value
        try await finishHiddenOutput(fixture, expectedRaw: "synthetic raw")
        #expect(fixture.events.count == 2)
    }

    @Test func eligibleStartupFailureHidesAndCleansBeforeWatchdog() async throws {
        let startGate = QuickRecordStartGate()
        let fixture = ImmediateDismissFixture(startGate: startGate, startFails: true)
        defer { fixture.remove() }
        await fixture.launch()
        let start = Task { await fixture.hotkeys.press() }
        await startGate.waitUntilEntered()
        fixture.recording.recognizeApple("synthetic Apple evidence")
        await fixture.hotkeys.release()
        fixture.expectVisibleAndBusy()
        await startGate.release()
        await start.value

        fixture.expectClean()
        assertQuickRecordTimingEvents(fixture)
        #expect(fixture.recording.stopCallCount == 0)
        #expect(fixture.recording.discardCallCount == 1)
        #expect(!fixture.refinement.isWaiting)
        #expect(fixture.clipboard.copied.isEmpty)
        #expect(fixture.saved.isEmpty)
    }

    @Test func recognitionCancellationHidesAndReleasesWithoutDownstreamOutput() async {
        let fixture = ImmediateDismissFixture(stopError: CancellationError())
        defer { fixture.remove() }
        await fixture.launch()
        await fixture.hotkeys.press()
        await fixture.hotkeys.release()

        fixture.expectClean()
        assertQuickRecordTimingEvents(fixture)
        #expect(fixture.recording.stopCallCount == 1)
        #expect(fixture.recording.discardCallCount == 0)
        #expect(!fixture.refinement.isWaiting)
        #expect(fixture.clipboard.copied.isEmpty)
        #expect(fixture.saved.isEmpty)
    }

    @Test func eligibleEmptyFinalHidesAtNoResultBoundaryAndReleases() async throws {
        let stopGate = QuickRecordStartGate()
        let fixture = ImmediateDismissFixture(stopGate: stopGate, hasResult: false)
        defer { fixture.remove() }
        await fixture.launch()
        await fixture.hotkeys.press()
        fixture.recording.recognizeApple("synthetic Apple evidence")
        let release = Task { await fixture.hotkeys.release() }
        await stopGate.waitUntilEntered()
        fixture.expectVisibleAndBusy()
        fixture.transcription.sendFinalText("")
        await stopGate.release()
        await release.value

        fixture.expectClean()
        assertQuickRecordTimingEvents(fixture)
        #expect(fixture.recording.stopCallCount == 1)
        #expect(fixture.recording.discardCallCount == 0)
        #expect(!fixture.refinement.isWaiting)
        #expect(fixture.clipboard.copied.isEmpty)
        #expect(fixture.saved.isEmpty)
    }

    @Test func oldRecognitionCallbackAndExpiredWatchdogCannotHideNextPanel() async throws {
        let fixture = ImmediateDismissFixture(stopFails: true)
        defer { fixture.remove() }
        await fixture.launch(recognitionTimeout: .milliseconds(100))
        await fixture.hotkeys.press()
        let model = try #require(fixture.model)
        let oldRecognitionEnded = model.onRecognitionEnded
        await fixture.hotkeys.release()
        fixture.expectClean()
        assertQuickRecordTimingEvents(fixture)

        fixture.model = model
        await fixture.hotkeys.press()
        oldRecognitionEnded?()
        // 等待注入的旧 watchdog 预算过期，确认已取消的定时任务不能影响新会话。
        try await Task.sleep(for: .milliseconds(150))
        #expect(fixture.visible)
        #expect(fixture.source == .quickRecording)
        #expect(fixture.events.count == 2)
        #expect(fixture.closes == 1)
        #expect(fixture.ends == 1)
        #expect(fixture.saved.isEmpty)
        await model.cancelFromPanel()
        #expect(!fixture.visible)
        #expect(fixture.source == nil)
        #expect(fixture.closes == 2)
        #expect(fixture.ends == 2)
        #expect(fixture.events.count == 2)
    }

    private func finishHiddenOutput(_ fixture: ImmediateDismissFixture, expectedRaw: String) async throws {
        try await waitForDismissBoundary { fixture.refinement.isWaiting }
        fixture.expectHiddenAndBusy()
        fixture.refinement.finish()
        try await waitForDismissBoundary { fixture.clipboard.pasteCount == 1 }
        fixture.expectHiddenAndBusy()
        await fixture.clipboard.gate.release()
        try await waitForDismissBoundary { fixture.saved.count == 1 }
        fixture.expectHiddenAndBusy()
        await fixture.saveGate.release()
        try await waitForDismissBoundary { fixture.source == nil }
        fixture.expectClean()
        #expect(fixture.clipboard.copied == ["synthetic refined。"])
        #expect(fixture.clipboard.pasteCount == 1)
        #expect(fixture.saved.count == 1)
        #expect(fixture.saved.first?.0 == expectedRaw)
        #expect(fixture.saved.first?.1 == "synthetic refined。")
    }
}
#endif
