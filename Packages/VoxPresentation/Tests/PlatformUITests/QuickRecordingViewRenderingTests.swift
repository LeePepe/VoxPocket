#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import UIShared
import Vision
@testable import PlatformUI

@MainActor
final class QuickRecordingViewRenderingTests: XCTestCase {
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
            (.refining, "把刚才讨论的想法整理一下，明天我们一起确认下一步的计划。"),
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
    }

    /// ImageRenderer 不包含 AppKit 承载的滚动内容；实际宿主离屏渲染用于检查文字。
    private func render(
        status: RecorderStatus, transcript: String, initialTranscript: String? = nil,
        placement: QuickRecordingPlacement = .floating, scrollToTopBeforeUpdate: Bool = false
    ) async throws -> NSBitmapImageRep {
        let size = NSSize(width: QuickRecordingLayout.panelWidth, height: QuickRecordingLayout.panelHeight)
        let host = NSHostingView(rootView: QuickRecordingIslandView(
            status: status, transcript: initialTranscript ?? transcript, audioLevel: 0.6, elapsed: 8, placement: placement
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
            host.rootView = QuickRecordingIslandView(status: status, transcript: transcript, audioLevel: 0.6, elapsed: 8, placement: placement)
            try await Task.sleep(for: .milliseconds(450))
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

    private static let notchedPlacement = QuickRecordingPlacement(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 40, width: 1512, height: 906),
        cameraRect: CGRect(x: 660, y: 946, width: 192, height: 36)
    )
}
#endif
