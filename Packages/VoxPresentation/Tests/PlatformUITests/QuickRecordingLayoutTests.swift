#if os(macOS)
import XCTest
@testable import PlatformUI

final class QuickRecordingLayoutTests: XCTestCase {
    func testQuickRecordingLayoutUsesCompactPillSize() {
        XCTAssertEqual(QuickRecordingLayout.pillWidth, 132)
        XCTAssertEqual(QuickRecordingLayout.pillHeight, 34)
        XCTAssertEqual(QuickRecordingLayout.panelWidth, 164)
        XCTAssertEqual(QuickRecordingLayout.panelHeight, 58)
    }

    func testQuickRecordingTopInsetMovesPanelUp() {
        XCTAssertEqual(QuickRecordingLayout.topInset, 120)
    }
}
#endif
