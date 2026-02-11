#if os(macOS)
import XCTest
@testable import PlatformUI

final class QuickRecordingLayoutTests: XCTestCase {
    func testQuickRecordingLayoutUsesCompactPillSize() {
        XCTAssertEqual(QuickRecordingLayout.pillWidth, 220)
        XCTAssertEqual(QuickRecordingLayout.pillHeight, 56)
        XCTAssertEqual(QuickRecordingLayout.panelWidth, 240)
        XCTAssertEqual(QuickRecordingLayout.panelHeight, 64)
    }

    func testQuickRecordingTopInsetMovesPanelUp() {
        XCTAssertEqual(QuickRecordingLayout.topInset, 120)
    }
}
#endif
