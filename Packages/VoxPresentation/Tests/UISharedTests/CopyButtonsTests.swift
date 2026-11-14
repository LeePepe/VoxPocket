import XCTest
import SwiftUI
@testable import UIShared

@MainActor
final class CopyButtonsTests: XCTestCase {
    func testBottomCopyInvokesHandler() {
        var didCopy = false
        let view = BottomControls(
            status: .idle,
            onStopOrRestart: {},
            onCopy: { didCopy = true },
            onNewSession: {}
        )

        view.onCopy()
        XCTAssertTrue(didCopy)
    }

    func testRawTranscriptCopyDisabledWhenEmpty() {
        let view = RawTranscriptView(rawText: "", status: .idle, canCopyRaw: false, onCopyRaw: {})
        XCTAssertFalse(view.canCopyRaw)
    }

    func testRefinedTextPaneDoesNotRequireStatusLabel() {
        _ = RefinedTextPane(text: "hello")
        XCTAssertTrue(true)
    }

    func testGestureControllerUsesProductReleaseOrdering() {
        var now = 0.0
        let controller = RecorderGestureController(now: { now })
        XCTAssertEqual(controller.begin(isRecording: false), .start)
        now = 0.3
        XCTAssertEqual(controller.end(), .stop)
        XCTAssertEqual(controller.end(), .none)
    }
}
