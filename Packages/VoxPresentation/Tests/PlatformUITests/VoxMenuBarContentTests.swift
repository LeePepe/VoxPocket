#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import PlatformUI

@MainActor
final class VoxMenuBarContentTests: XCTestCase {
    func testStatusDoesNotPromiseRecordingOrRemoteServiceReadiness() {
        XCTAssertEqual(MenuBarConfigurationStatus.loading.title, "正在加载本机配置…")
        XCTAssertEqual(MenuBarConfigurationStatus.loaded.title, "配置已加载")
        XCTAssertEqual(MenuBarConfigurationStatus.failed.title, "本机配置需要检查")
    }

    func testConstructingAnyMenuStateDoesNotRunInjectedActions() {
        for status in MenuBarConfigurationStatus.allCases {
            var actions: [String] = []
            let view = VoxMenuBarContent(configurationStatus: status,
                                         onOpenMainWindow: { actions.append("main") },
                                         onOpenSettings: { actions.append("settings") },
                                         onQuit: { actions.append("quit") })
            _ = view.body
            XCTAssertTrue(actions.isEmpty)
            // 配置失败不取消恢复入口；平台生命周期动作仍完全由宿主注入。
            view.onOpenMainWindow()
            view.onOpenSettings()
            view.onQuit()
            XCTAssertEqual(actions, ["main", "settings", "quit"])
        }
    }

    func testFailedConfigurationStillAllowsButtonClicks() async throws {
        var actions: [String] = []
        let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 12) {
            VoxMenuBarContent(configurationStatus: .failed,
                              onOpenMainWindow: { actions.append("main") },
                              onOpenSettings: { actions.append("settings") },
                              onQuit: { actions.append("quit") })
        }.padding(16).frame(width: 280, height: 200, alignment: .topLeading))
        let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 280, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        // 只给测试窗口发送鼠标事件；点击真实 SwiftUI Button，不访问其他应用或全局鼠标。
        for topOffset in [70.0, 105.0, 154.0] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: NSPoint(x: 60, y: 200 - topOffset), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                panel.sendEvent(event)
            }
            await Task.yield()
        }
        XCTAssertEqual(actions, ["main", "settings", "quit"])
    }

    func testAllStatesRenderWithoutStartingAppServices() async throws {
        for status in MenuBarConfigurationStatus.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let view = VStack(alignment: .leading, spacing: 12) {
                    VoxMenuBarContent(configurationStatus: status,
                                      onOpenMainWindow: {}, onOpenSettings: {}, onQuit: {})
                }
                .padding(16)
                .frame(width: 280)
                .background(scheme == .dark ? Color(nsColor: .black) : .white)
                .environment(\.colorScheme, scheme)
                let image = try XCTUnwrap(ImageRenderer(content: view).cgImage)
                XCTAssertEqual(image.width, 280)
                XCTAssertGreaterThan(image.height, 100)
                if let directory = ProcessInfo.processInfo.environment["VOX_MENU_RENDER_DIR"] {
                    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    let url = URL(fileURLWithPath: directory).appendingPathComponent("menu-\(status)-\(scheme).png")
                    try await Task.detached { try png.write(to: url) }.value
                }
            }
        }
    }

}
#endif
