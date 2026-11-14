import XCTest
@testable import UIShared

@MainActor
final class RecorderGestureControllerTests: XCTestCase {
    func testHoldStartsImmediatelyAndStopsOnceOnRelease() {
        let controller = RecorderGestureController()
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(controller.begin(isRecording: false, now: start), .start)
        XCTAssertEqual(controller.end(now: start.addingTimeInterval(0.28)), .stop)
        XCTAssertEqual(controller.end(now: start.addingTimeInterval(1)), .none)
    }

    func testShortTapKeepsCaptureForTapToggleFallback() {
        let controller = RecorderGestureController()
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(controller.begin(isRecording: false, now: start), .start)
        XCTAssertEqual(controller.end(now: start.addingTimeInterval(0.1)), .none)
        XCTAssertEqual(controller.activate(isRecording: true), .stop)
    }

    func testAsyncStartReleaseDoesNotStopExistingCapture() {
        let controller = RecorderGestureController()
        XCTAssertEqual(controller.begin(isRecording: true), .none)
        XCTAssertEqual(controller.end(now: Date().addingTimeInterval(1)), .none)
        XCTAssertEqual(controller.activate(isRecording: true), .stop)
    }

    func testCancelClearsOwnedGesture() {
        let controller = RecorderGestureController()
        XCTAssertEqual(controller.begin(isRecording: false), .start)
        controller.cancel()
        XCTAssertEqual(controller.end(now: Date().addingTimeInterval(1)), .none)
    }
}
