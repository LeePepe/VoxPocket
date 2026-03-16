#if os(macOS)
import XCTest
@testable import PlatformUI

final class QuickRecordingLayoutTests: XCTestCase {
    func testQuickRecordingLayoutUsesCompactPillSize() {
        XCTAssertEqual(QuickRecordingLayout.pillWidth, 132)
        XCTAssertEqual(QuickRecordingLayout.pillHeight, 34)
        XCTAssertEqual(QuickRecordingLayout.panelWidth, QuickRecordingLayout.pillWidth)
        XCTAssertEqual(QuickRecordingLayout.panelHeight, QuickRecordingLayout.pillHeight)
    }

    func testQuickRecordingTextOverlayUsesCompactInsets() {
        XCTAssertEqual(QuickRecordingLayout.textHorizontalInset, 12)
        XCTAssertEqual(QuickRecordingLayout.textLeftFadeWidth, 24)
    }

    func testQuickRecordingTopInsetMovesPanelUp() {
        XCTAssertEqual(QuickRecordingLayout.topInset, 120)
    }
}
#endif
