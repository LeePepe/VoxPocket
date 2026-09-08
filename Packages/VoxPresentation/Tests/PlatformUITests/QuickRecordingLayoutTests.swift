#if os(macOS)
import XCTest
import UIShared
@testable import PlatformUI

final class QuickRecordingLayoutTests: XCTestCase {
    func testStreamingTextDoesNotRepeatedlyResizeExpandedIsland() {
        let first = QuickRecordingLayout.islandSize(for: .listening, showsTranscript: true, textHeight: 30)
        let next = QuickRecordingLayout.islandSize(for: .listening, showsTranscript: true, textHeight: 100)
        XCTAssertEqual(first, next)
    }
    func testWaitingAndExpandedProportionsMatchApprovedDesign() {
        XCTAssertEqual(QuickRecordingLayout.islandSize(for: .listening).width, 280)
        XCTAssertEqual(QuickRecordingLayout.islandSize(for: .listening, showsTranscript: true).width, 480)
        XCTAssertEqual(QuickRecordingLayout.islandCorner(for: .listening), 24)
        XCTAssertEqual(QuickRecordingLayout.readingHeight, 80)
    }

    func testShortAndLongTranscriptsShareStableReadingEnvelope() {
        let short = QuickRecordingLayout.islandSize(for: .listening, showsTranscript: true, textHeight: 74)
        let long = QuickRecordingLayout.islandSize(for: .listening, showsTranscript: true, textHeight: 1000)
        XCTAssertEqual(short.height, long.height)
        XCTAssertEqual(long.height, QuickRecordingLayout.panelHeight)
    }

    func testNotchedPanelAttachesToActualScreenTop() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let camera = CGRect(x: 660, y: 946, width: 192, height: 36)
        let placement = QuickRecordingPlacement(screenFrame: screen, visibleFrame: screen.insetBy(dx: 0, dy: 36), cameraRect: camera)
        XCTAssertEqual(placement.panelFrame.maxY, screen.maxY)
        XCTAssertEqual(placement.panelFrame.midX, camera.midX)
        XCTAssertEqual(placement.cameraSize, camera.size)
        XCTAssertTrue(placement.isAttached)
        let waiting = QuickRecordingLayout.size(for: .listening, showsTranscript: false, placement: placement)
        XCTAssertGreaterThanOrEqual(waiting.width, camera.width + QuickRecordingLayout.cameraWingSpace)
    }

    func testExternalScreenUsesVisibleFrameAndNoFakeCamera() {
        let screen = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
        let visible = CGRect(x: -1870, y: 160, width: 1870, height: 1015)
        let placement = QuickRecordingPlacement(screenFrame: screen, visibleFrame: visible)
        XCTAssertFalse(placement.isAttached)
        XCTAssertEqual(placement.cameraSize, .zero)
        XCTAssertEqual(placement.panelFrame.midX, visible.midX)
        XCTAssertEqual(placement.panelFrame.maxY, visible.maxY - 12)
        XCTAssertTrue(visible.contains(placement.panelFrame))
    }

    func testNarrowScreenClampsPanelAndAvoidsUnusableCameraWings() {
        let screen = CGRect(x: 700, y: -900, width: 390, height: 700)
        let camera = CGRect(x: 770, y: -230, width: 250, height: 30)
        let placement = QuickRecordingPlacement(screenFrame: screen, visibleFrame: screen, cameraRect: camera)
        XCTAssertEqual(placement.panelFrame.width, 358)
        XCTAssertFalse(placement.isAttached)
        XCTAssertTrue(screen.contains(placement.panelFrame))
    }

    func testAllStatesFitHostIncludingErrorWithTranscript() {
        for status in RecorderStatus.allCases {
            for showsTranscript in [false, true] {
                let size = QuickRecordingLayout.size(for: status, showsTranscript: showsTranscript, placement: .floating)
                XCTAssertLessThanOrEqual(size.width, QuickRecordingLayout.panelWidth)
                XCTAssertLessThanOrEqual(size.height, QuickRecordingLayout.panelHeight)
            }
        }
    }

    func testInvalidCameraOutsideScreenDoesNotCreateNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let placement = QuickRecordingPlacement(screenFrame: screen, visibleFrame: screen,
                                                cameraRect: CGRect(x: 2000, y: 900, width: 180, height: 30))
        XCTAssertFalse(placement.isAttached)
    }

    func testProcessingStagesDoNotResizeVisibleText() {
        let sizes = [RecorderStatus.listening, .transcribing, .refining, .done, .error].map {
            QuickRecordingLayout.islandSize(for: $0, showsTranscript: true)
        }
        XCTAssertTrue(sizes.allSatisfy { $0 == sizes.first })
    }
}
#endif
