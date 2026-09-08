#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import UIShared
import Vision
import ImageIO
import UniformTypeIdentifiers
@testable import PlatformUI

@MainActor
final class QuickRecordingViewRenderingTests: XCTestCase {
    func testTextDoesNotAppearClippedDuringInitialExpansion() async throws {
        let early = try await render(status: .listening, transcript: "New words visible.",
                                     initialTranscript: "", updateWait: .milliseconds(60))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(early.cgImage)).perform([request])
        let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
        XCTAssertFalse(words.contains("words"))
    }

    /// 使用实际 SwiftUI 过渡帧展示动画，不访问麦克风或用户文字。
    func testExportExpansionAnimationWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOX_ISLAND_RENDER_DIR"] else { return }
        let host = NSHostingView(rootView: QuickRecordingIslandView(status: .listening, transcript: "", placement: Self.notchedPlacement))
        let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: QuickRecordingLayout.panelWidth,
                                               height: QuickRecordingLayout.panelHeight),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        let url = URL(fileURLWithPath: directory).appendingPathComponent("expansion.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 5, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (index, delay) in [0, 60, 60, 80, 120].enumerated() {
            try await Task.sleep(for: .milliseconds(delay))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage)
            CGImageDestinationAddImage(destination, image,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: index == 4 ? 1.2 : 0.08]] as CFDictionary)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("motion-\(index).png"))
            if index == 0 {
                host.rootView = QuickRecordingIslandView(status: .listening, transcript: "明天开会讨论下一步计划。", placement: Self.notchedPlacement)
            }
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testCompactStatesDoNotRenderStatusCopyOrTimer() async throws {
        for status in RecorderStatus.allCases {
            let bitmap = try await render(status: status, transcript: "")
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
            for unwanted in ["正在", "准备", "实时", "松开", "取消", "00:"] {
                XCTAssertFalse(words.contains(unwanted), "\(status) contains unnecessary visible copy")
            }
        }
    }

    func testRenderedTranscriptIsVisibleOnlyInActiveStates() async throws {
        for status in RecorderStatus.allCases {
            let bitmap = try await render(status: status, transcript: "Visible transcript sample.")
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            XCTAssertEqual(words.contains("Visible transcript sample"), status != .idle, "\(status) transcript visibility")
        }
    }

    func testAllStatesRenderWithinFixedHost() throws {
        for status in RecorderStatus.allCases {
            for transcript in ["", "把刚才讨论的想法整理一下，明天我们一起确认下一步的计划。",
                               String(repeating: "这是一段用于验证换行与滚动的测试文字。", count: 30)] {
                let renderer = ImageRenderer(content: QuickRecordingIslandView(
                    status: status, transcript: transcript, audioLevel: 0.6
                ))
                let rendered = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(rendered.width, Int(QuickRecordingLayout.panelWidth))
                XCTAssertEqual(rendered.height, Int(QuickRecordingLayout.panelHeight))
            }
        }
    }

    func testLongTranscriptScrollsToLatestTextAfterUpdate() async throws {
        let transcript = String(repeating: "Earlier recognized text.\n", count: 40) + "Latest sentence visible."
        let bitmap = try await render(status: .listening, transcript: transcript, initialTranscript: "First sentence.")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(words.contains("Latest sentence visible"))
        XCTAssertFalse(words.contains("First sentence"))
    }

    func testManualScrollIsPreservedWhenNewTextArrives() async throws {
        let original = "Oldest sentence visible.\n" + String(repeating: "Earlier recognized text.\n", count: 40)
        let bitmap = try await render(status: .listening, transcript: original + "Newest addition.",
                                      initialTranscript: original, scrollToTopBeforeUpdate: true)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(words.contains("Oldest sentence visible"))
        XCTAssertFalse(words.contains("Newest addition"))
    }

    func testCameraCutoutIsTransparentOnlyOnNotchedScreen() async throws {
        let notched = try await render(status: .listening, transcript: "Sample", placement: Self.notchedPlacement)
        let floating = try await render(status: .listening, transcript: "Sample")
        XCTAssertLessThan(try XCTUnwrap(notched.colorAt(x: notched.pixelsWide / 2, y: 10)).alphaComponent, 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(floating.colorAt(x: floating.pixelsWide / 2, y: 10)).alphaComponent, 0.95)
    }

    /// 仅显式指定路径时导出人工构造的测试文案，不触碰用户录音。
    func testExportDesignContactSheetWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOX_ISLAND_RENDER_DIR"] else { return }
        let samples: [(RecorderStatus, String)] = [
            (.listening, ""),
            (.listening, "我想做一个更安静的语音工具，\n按下 Fn，就能把想法留下来。"),
            (.refining, "明天开会讨论下一步计划。"),
            (.listening, String(repeating: "这是更早识别到的内容，需要自动滚动。\n", count: 20) + "这是最新识别到的句子。"),
            (.error, "")
        ]
        for (index, sample) in samples.enumerated() {
            let bitmap = try await render(status: sample.0, transcript: sample.1, placement: Self.notchedPlacement)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("island-\(index).png"))
        }
        let bitmap = try await render(status: .error, transcript: "已识别的原文不会因为错误而消失。")
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("island-error-text.png"))
        for status in RecorderStatus.allCases {
            let bitmap = try await render(status: status, transcript: status == .idle ? "" : "明天开会讨论下一步计划。",
                                          placement: Self.notchedPlacement)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("state-\(status).png"))
        }
        let transparent = try await render(status: .refining, transcript: "明天开会讨论下一步计划。", placement: Self.notchedPlacement)
        try writeLightComposite(transparent, to: URL(fileURLWithPath: directory).appendingPathComponent("light-background.png"))
    }

    /// ImageRenderer 不包含 AppKit 承载的滚动内容；实际宿主离屏渲染用于检查文字。
    private func render(
        status: RecorderStatus, transcript: String, initialTranscript: String? = nil,
        placement: QuickRecordingPlacement = .floating, scrollToTopBeforeUpdate: Bool = false,
        updateWait: Duration = .milliseconds(450)
    ) async throws -> NSBitmapImageRep {
        let size = NSSize(width: QuickRecordingLayout.panelWidth, height: QuickRecordingLayout.panelHeight)
        let host = NSHostingView(rootView: QuickRecordingIslandView(
            status: status, transcript: initialTranscript ?? transcript, audioLevel: 0.6, placement: placement
        ))
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(450))
        if scrollToTopBeforeUpdate {
            let scroll = try XCTUnwrap(findScrollView(in: host))
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(100))
        }
        if initialTranscript != nil {
            host.rootView = QuickRecordingIslandView(status: status, transcript: transcript, audioLevel: 0.6, placement: placement)
            try await Task.sleep(for: updateWait)
        }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }

    private func writeLightComposite(_ bitmap: NSBitmapImageRep, to url: URL) throws {
        let size = bitmap.size
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor(Neutral.slate.palette(isDark: false).inner).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: size).draw(in: NSRect(origin: .zero, size: size))
        canvas.unlockFocus()
        let output = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(canvas.tiffRepresentation)))
        try XCTUnwrap(output.representation(using: .png, properties: [:])).write(to: url)
    }

    private static let notchedPlacement = QuickRecordingPlacement(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 40, width: 1512, height: 906),
        cameraRect: CGRect(x: 660, y: 946, width: 192, height: 36)
    )
}
#endif
