#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import UIShared

/// 主 UI 的真实背景组件与阶段色组件的同源对照，所有文字均为测试样本。
@MainActor
final class PhaseColorReferenceTests: XCTestCase {
    func testPhaseSurfacesHaveStableSizeAcrossAllStates() throws {
        for status in RecorderStatus.allCases {
            let renderer = ImageRenderer(content: QuickRecordingPhaseSurface(status: status, audioLevel: 0.6)
                .frame(width: 480, height: 148))
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, 480)
            XCTAssertEqual(image.height, 148)
        }
    }

    func testExportMainUIAndPhaseReferencesWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOX_PHASE_RENDER_DIR"] else { return }
        for status in RecorderStatus.allCases {
            let main = BackgroundAtmosphere(status: status, audioLevel: 0.6)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("主界面背景 · \(String(describing: status))").font(.system(size: 14))
                        Text("明天开会讨论下一步计划。").font(.system(size: 24))
                    }.foregroundStyle(Theme.light.palette.textPrimary).padding(32)
                }
                .frame(width: 620, height: 420).environment(\.colorScheme, .light)
            try await export(main, size: NSSize(width: 620, height: 420),
                             to: URL(fileURLWithPath: directory).appendingPathComponent("main-\(status).png"))
            let surface = QuickRecordingPhaseSurface(status: status, audioLevel: 0.6)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 24) {
                        Circle().fill(QuickRecordingColors.status(status)).frame(width: 8, height: 8)
                        Text("明天开会讨论下一步计划。")
                            .font(.system(size: 20)).foregroundStyle(QuickRecordingColors.neutrals.text1)
                    }.padding(24)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(
                    LinearGradient(colors: QuickRecordingColors.rim(status), startPoint: .topLeading, endPoint: .bottomTrailing)))
            try await export(surface, size: NSSize(width: 480, height: 148),
                             to: URL(fileURLWithPath: directory).appendingPathComponent("surface-\(status).png"))
        }
    }

    private func export<V: View>(_ view: V, size: NSSize, to url: URL) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(550))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)).alphaComponent, 0.9)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try await Task.detached { try png.write(to: url) }.value
    }
}

#endif
