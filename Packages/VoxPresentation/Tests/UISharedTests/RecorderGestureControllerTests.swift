import XCTest
@testable import UIShared

@MainActor
final class RecorderGestureControllerTests: XCTestCase {
    func testTwoPhysicalTapsStartThenStopAndAccessibleActivationStillWorks() async {
        var time = 100.0
        let controller = RecorderGestureController(now: { time })
        let probe = CaptureProbe()
        controller.pressBegan(probe.capture)
        await controller.waitForSettled()
        time += 0.1
        controller.pressEnded()
        XCTAssertEqual(probe.events, ["start"])
        XCTAssertTrue(probe.recording)
        controller.pressBegan(probe.capture)
        time += 0.1
        controller.pressEnded()
        controller.pressEnded()
        await controller.waitForSettled()
        XCTAssertEqual(probe.events, ["start", "stop"])
        controller.activate(probe.capture)
        await controller.waitForSettled()
        controller.activate(probe.capture)
        await controller.waitForSettled()
        XCTAssertEqual(probe.events, ["start", "stop", "start", "stop"])
    }

    func testHeldReleaseWaitsForPausedStartAndStopsExactlyOnce() async {
        var time = 100.0
        let gate = RecorderTestGate()
        let controller = RecorderGestureController(now: { time })
        let probe = CaptureProbe(gate: gate)
        controller.pressBegan(probe.capture)
        await gate.waitForEntries()
        controller.pressBegan(probe.capture)
        controller.activate(probe.capture)
        time += 0.3
        controller.pressEnded()
        controller.pressEnded()
        XCTAssertEqual(probe.events, ["start-requested"])
        await gate.releaseNext()
        await controller.waitForSettled()
        XCTAssertEqual(probe.events, ["start-requested", "start", "stop"])
        XCTAssertFalse(probe.recording)
    }

    func testCancellationDuringPausedStartAndGestureResetCannotStrandCapture() async {
        let gate = RecorderTestGate()
        let controller = RecorderGestureController()
        let probe = CaptureProbe(gate: gate)
        controller.pressBegan(probe.capture)
        await gate.waitForEntries()
        controller.gestureReset()
        controller.cancel()
        controller.pressEnded()
        await gate.releaseNext()
        await controller.waitForSettled()
        XCTAssertEqual(probe.events, ["start-requested", "start", "cancel"])
        XCTAssertFalse(probe.recording)
    }

    func testProcessingIgnoresPhysicalAndAccessiblePresses() async {
        let controller = RecorderGestureController()
        let probe = CaptureProbe()
        probe.processing = true
        controller.pressBegan(probe.capture)
        controller.pressEnded()
        controller.activate(probe.capture)
        await controller.waitForSettled()
        XCTAssertTrue(probe.events.isEmpty)
    }
}

@MainActor
private final class CaptureProbe {
    var events: [String] = []
    var recording = false
    var processing = false
    let gate: RecorderTestGate?
    init(gate: RecorderTestGate? = nil) { self.gate = gate }
    var capture: RecorderGestureController.Capture {
        .init(isRecording: recording, isProcessing: processing, start: {
            if let gate = self.gate {
                self.events.append("start-requested")
                await gate.suspend()
            }
            self.recording = true
            self.events.append("start")
        }, stop: {
            XCTAssertTrue(self.recording)
            self.events.append("stop")
            self.recording = false
        }, cancel: {
            self.events.append("cancel")
            self.recording = false
        })
    }
}
