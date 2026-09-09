#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import UIShared

@MainActor
final class AtmosphereSurfaceConsistencyTests: XCTestCase {
    func testMainAndIslandRenderMatchingSurfacesInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for status in [RecorderStatus.idle, .listening, .refining, .error] {
                let main = try await render(BackgroundAtmosphere(status: status), scheme: scheme)
                let island = try await render(QuickRecordingPhaseSurface(status: status), scheme: scheme)
                for x in [0.2, 0.5, 0.8] {
                    for y in [0.2, 0.5, 0.8] {
                        let a = try pixel(main, x: x, y: y)
                        let b = try pixel(island, x: x, y: y)
                        for component in 0..<3 {
                            XCTAssertEqual(a[component], b[component], accuracy: 0.03,
                                           "同一阶段与外观必须共用底材：\(scheme), \(status)")
                        }
                    }
                }
            }
        }
    }

    private func render<V: View>(_ view: V, scheme: ColorScheme) async throws -> NSBitmapImageRep {
        let size = NSSize(width: 480, height: 148)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .clipped().environment(\.colorScheme, scheme))
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func pixel(_ bitmap: NSBitmapImageRep, x: Double, y: Double) throws -> [CGFloat] {
        let color = try XCTUnwrap(bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * x),
                                                y: Int(Double(bitmap.pixelsHigh) * y))?.usingColorSpace(.sRGB))
        return [color.redComponent, color.greenComponent, color.blueComponent]
    }
}
#endif
