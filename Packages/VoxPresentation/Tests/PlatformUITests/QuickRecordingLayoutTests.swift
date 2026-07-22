#if os(macOS)
import XCTest
import UIShared
@testable import PlatformUI

final class QuickRecordingLayoutTests: XCTestCase {
    func testIslandCollapsesWhenIdle() {
        let idle = QuickRecordingLayout.islandSize(for: .idle)
        XCTAssertEqual(idle.width, 72)
        XCTAssertEqual(idle.height, 28)
        XCTAssertEqual(QuickRecordingLayout.islandCorner(for: .idle), 14)
    }

    func testIslandExpandsWhileActive() {
        for status in [RecorderStatus.listening, .transcribing, .refining] {
            let size = QuickRecordingLayout.islandSize(for: status)
            XCTAssertEqual(size.width, 120, "\(status) width")
            XCTAssertEqual(size.height, 54, "\(status) height")
            XCTAssertEqual(QuickRecordingLayout.islandCorner(for: status), 22, "\(status) corner")
        }
    }

    func testIslandTerminalStatesAreCompact() {
        for status in [RecorderStatus.done, .error] {
            let size = QuickRecordingLayout.islandSize(for: status)
            XCTAssertEqual(size.width, 72, "\(status) width")
            XCTAssertEqual(size.height, 44, "\(status) height")
            XCTAssertEqual(QuickRecordingLayout.islandCorner(for: status), 20, "\(status) corner")
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
