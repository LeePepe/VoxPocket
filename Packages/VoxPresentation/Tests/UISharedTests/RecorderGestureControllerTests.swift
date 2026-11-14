import XCTest
@testable import UIShared

@MainActor
final class RecorderGestureControllerTests: XCTestCase {
    func testHoldStartsImmediatelyAndStopsOnceOnRelease() {
        var time = 100.0
        let controller = RecorderGestureController(now: { time })
        XCTAssertEqual(controller.begin(isRecording: false), .start)
        time += 0.28
        XCTAssertEqual(controller.end(), .stop)
        XCTAssertEqual(controller.end(), .none)
    }

    func testShortTapKeepsCaptureForTapToggleFallback() {
        var time = 100.0
        let controller = RecorderGestureController(now: { time })
        XCTAssertEqual(controller.begin(isRecording: false), .start)
        time += 0.1
        XCTAssertEqual(controller.end(), .none)
        XCTAssertEqual(controller.activate(isRecording: true), .stop)
    }

    func testAsyncStartReleaseDoesNotStopExistingCapture() {
        let controller = RecorderGestureController()
        XCTAssertEqual(controller.begin(isRecording: true), .none)
        XCTAssertEqual(controller.end(), .none)
        XCTAssertEqual(controller.activate(isRecording: true), .stop)
    }

    func testCancelClearsOwnedGesture() {
        let controller = RecorderGestureController()
        XCTAssertEqual(controller.begin(isRecording: false), .start)
        controller.cancel()
        XCTAssertEqual(controller.end(), .none)
    }
}
