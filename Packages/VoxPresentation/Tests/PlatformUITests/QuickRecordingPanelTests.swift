#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import PlatformUI

@MainActor
final class QuickRecordingPanelTests: XCTestCase {
    func testOnlyValidTopAttachmentOverridesSystemMenuBarDisplacement() {
        let screen = CGRect(x: 0, y: -1329, width: 2056, height: 1329)
        let camera = CGRect(x: 928, y: -38, width: 200, height: 38)
        let placement = QuickRecordingPlacement(screenFrame: screen, visibleFrame: screen, cameraRect: camera)
        let panel = QuickRecordingPanel(contentRect: placement.panelFrame,
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.placement = placement
        let proposed = placement.panelFrame
        let displaced = proposed.offsetBy(dx: 0, dy: -39)
        XCTAssertEqual(panel.resolvedFrame(proposed: proposed, constrained: displaced,
                                          screenFrame: screen, screenHasCamera: true), proposed)
        XCTAssertEqual(panel.resolvedFrame(proposed: proposed, constrained: displaced,
                                          screenFrame: screen, screenHasCamera: false), displaced)
        for invalid in [proposed.offsetBy(dx: 0, dy: -20), proposed.offsetBy(dx: -2000, dy: 0),
                        proposed.insetBy(dx: -10, dy: 0), proposed.offsetBy(dx: 100, dy: 0)] {
            XCTAssertEqual(panel.resolvedFrame(proposed: invalid, constrained: displaced,
                                              screenFrame: screen, screenHasCamera: true), displaced)
        }
        panel.placement = .floating
        XCTAssertEqual(panel.resolvedFrame(proposed: proposed, constrained: displaced,
                                          screenFrame: screen, screenHasCamera: true), displaced)
    }

    func testFloatingPanelStaysAttachedToRealNotchAfterPresentation() async throws {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            throw XCTSkip("原生贴顶集成测试需要真实刘海屏；几何边界由独立测试覆盖")
        }
        let camera = CGRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                            width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
        let placement = QuickRecordingPlacement(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, cameraRect: camera)
        let panel = QuickRecordingPanel(contentRect: CGRect(origin: .zero, size: placement.panelFrame.size),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.placement = placement
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        XCTAssertEqual(panel.constrainFrameRect(placement.panelFrame, to: screen), placement.panelFrame,
                       "系统窗口约束回调不得把贴顶岛体推到菜单栏下方")
        let host = NSHostingView(rootView: QuickRecordingIslandView(status: .idle, transcript: ""))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        let controller = NSWindowController(window: panel)
        panel.setFrame(placement.panelFrame, display: true)
        host.rootView = QuickRecordingIslandView(status: .idle, transcript: "", placement: placement)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 1)
        XCTAssertEqual(panel.frame.midX, camera.midX, accuracy: 1)
        XCTAssertEqual(host.bounds.size, placement.panelFrame.size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let wingX = Int(((host.bounds.width - camera.width) / 2 - 20) * scale)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: wingX, y: Int(10 * scale))).alphaComponent, 0.95)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: Int(10 * scale))).alphaComponent, 0.05)
        if let directory = ProcessInfo.processInfo.environment["VOX_ISLAND_RENDER_DIR"] {
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent("appkit-notched-panel.png")
            try await Task.detached { try data.write(to: url) }.value
        }
        withExtendedLifetime(controller) {}
    }
}
#endif
