#if os(macOS)
import XCTest
import UIShared
@testable import PlatformUI

final class QuickRecordingLayoutTests: XCTestCase {
    func testIslandCollapsesWhenIdle() {
        let idle = QuickRecordingLayout.islandSize(for: .idle)
        XCTAssertEqual(idle.width, 148)
        XCTAssertEqual(idle.height, 36)
        XCTAssertEqual(QuickRecordingLayout.islandCorner(for: .idle), 18)
    }

    func testIslandExpandsWhileActive() {
        for status in [RecorderStatus.listening, .transcribing, .refining] {
            let size = QuickRecordingLayout.islandSize(for: status)
            XCTAssertEqual(size.width, 340, "\(status) width")
            XCTAssertEqual(size.height, 68, "\(status) height")
            XCTAssertEqual(QuickRecordingLayout.islandCorner(for: status), 28, "\(status) corner")
        }
    }

    func testIslandNeverExceedsHostPanel() {
        for status in RecorderStatus.allCases {
            let size = QuickRecordingLayout.islandSize(for: status)
            XCTAssertLessThanOrEqual(size.width, QuickRecordingLayout.panelWidth, "\(status) width fits host")
            XCTAssertLessThanOrEqual(size.height, QuickRecordingLayout.panelHeight, "\(status) height fits host")
        }
    }

    func testHostPanelEnvelope() {
        XCTAssertEqual(QuickRecordingLayout.panelWidth, 380)
        XCTAssertEqual(QuickRecordingLayout.panelHeight, 132)
    }

    func testQuickRecordingTopInsetMovesPanelUp() {
        XCTAssertEqual(QuickRecordingLayout.topInset, 120)
    }
}
#endif
