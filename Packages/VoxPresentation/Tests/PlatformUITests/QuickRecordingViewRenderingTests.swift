#if os(macOS)
import AppKit
import Combine
import SwiftUI
import XCTest
import UIShared
import Vision
import ImageIO
import UniformTypeIdentifiers
@testable import PlatformUI

@MainActor
final class QuickRecordingViewRenderingTests: XCTestCase {
    func testIslandFollowsAppearanceAndKeepsTextReadable() async throws {
        let light = try await render(status: .listening, transcript: "Readable sample.", colorScheme: .light)
        let dark = try await render(status: .listening, transcript: "Readable sample.", colorScheme: .dark)
        let a = try XCTUnwrap(light.colorAt(x: light.pixelsWide / 2, y: light.pixelsHigh - 12)?.usingColorSpace(.sRGB))
        let b = try XCTUnwrap(dark.colorAt(x: dark.pixelsWide / 2, y: dark.pixelsHigh - 12)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(a.redComponent + a.greenComponent + a.blueComponent,
                             b.redComponent + b.greenComponent + b.blueComponent + 0.8)
        for bitmap in [light, dark] {
            let words = try recognizedLines(bitmap).joined(separator: " ")
            XCTAssertTrue(words.contains("Readable sample"))
        }
    }

    func testExportBothAppearanceBoardsWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOX_ISLAND_RENDER_DIR"] else { return }
        for scheme in [ColorScheme.light, .dark] {
            var images: [NSBitmapImageRep] = []
            for status in RecorderStatus.allCases {
                images.append(try await render(status: status, transcript: status == .idle ? "" : "明天开会讨论下一步计划。",
                                                placement: Self.notchedPlacement, colorScheme: scheme))
            }
            let canvas = NSImage(size: NSSize(width: 1040, height: 640))
            canvas.lockFocus()
            NSColor(QuickRecordingColors.neutrals(for: scheme).bg).setFill()
            NSRect(x: 0, y: 0, width: 1040, height: 640).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor(QuickRecordingColors.neutrals(for: scheme).text1)
            ]
            ("\(scheme) · 主窗口同材质浮窗" as NSString).draw(at: NSPoint(x: 24, y: 610), withAttributes: attributes)
            for (index, bitmap) in images.enumerated() {
                let x = CGFloat(24 + (index % 2) * 512), y = CGFloat(430 - (index / 2) * 188)
                NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: bitmap.size)
                    .draw(in: NSRect(x: x, y: y, width: 480, height: 148))
                (String(describing: RecorderStatus.allCases[index]) as NSString)
                    .draw(at: NSPoint(x: x, y: y + 154), withAttributes: attributes)
            }
            canvas.unlockFocus()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(canvas.tiffRepresentation)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent("appearance-\(scheme).png")
            try await Task.detached { try png.write(to: url) }.value
        }
    }

    func testEntranceRevealsDownwardBeforeReachingFullSize() async throws {
        for placement in [QuickRecordingPlacement.floating, Self.notchedPlacement] {
            let early = try await render(status: .listening, transcript: "", placement: placement, initialWait: .milliseconds(60))
            let settled = try await render(status: .listening, transcript: "", placement: placement)
            let earlyBounds = try opaqueBounds(early)
            let settledBounds = try opaqueBounds(settled)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                XCTAssertEqual(earlyBounds, settledBounds, "减少动态效果时应立即显示完整岛体")
                continue
            }
            XCTAssertEqual(earlyBounds.midX, settledBounds.midX, accuracy: 2)
            XCTAssertLessThan(earlyBounds.width, settledBounds.width)
            XCTAssertLessThan(earlyBounds.maxY, settledBounds.maxY)
            if placement.isAttached {
                XCTAssertGreaterThan(earlyBounds.minY, settledBounds.minY)
            } else {
                XCTAssertEqual(earlyBounds.minY, settledBounds.minY, accuracy: 2)
            }
        }
    }

    func testReduceMotionShowsCompleteIslandAndTextImmediately() async throws {
        let bitmap = try await render(status: .listening, transcript: "Visible transcript sample.",
                                      initialWait: .milliseconds(80), reduceMotion: true)
        XCTAssertGreaterThan(try opaqueBounds(bitmap).height, 140)
        let words = try recognizedLines(bitmap).joined(separator: " ")
        XCTAssertTrue(words.contains("Visible transcript sample"), "Synthetic OCR \(bitmap.pixelsWide)x\(bitmap.pixelsHigh): \(words)")
    }

    /// 导出真实入场帧，分别检查独立胶囊与摄像头下缘起点，不访问录音服务。
    func testExportEntranceAnimationWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOX_ISLAND_RENDER_DIR"] else { return }
        for (name, placement) in [("floating", QuickRecordingPlacement.floating), ("notched", Self.notchedPlacement)] {
            let host = NSHostingView(rootView: QuickRecordingIslandView(status: .listening, transcript: "", placement: placement))
            let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 480, height: 148),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.contentView = host
            panel.orderFront(nil)
            defer { panel.orderOut(nil) }
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: directory).appendingPathComponent("entrance-\(name).gif") as CFURL,
                UTType.gif.identifier as CFString, 8, nil))
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for index in 0..<8 {
                if index > 0 { try await Task.sleep(for: .milliseconds(60)) }
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.cgImage),
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: index == 7 ? 1 : 0.06]] as CFDictionary)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let url = URL(fileURLWithPath: directory).appendingPathComponent("entrance-\(name)-\(index).png")
                try await Task.detached { try data.write(to: url) }.value
            }
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
    }

    func testPhaseSymbolDoesNotDimDuringColorTransition() async throws {
        let bitmap = try await render(status: .refining, transcript: "Sample", initialStatus: .transcribing,
                                      updateWait: .milliseconds(280))
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        var peakBlue: CGFloat = 0
        for x in Int(24 * scale)..<Int(48 * scale) {
            for y in Int(12 * scale)..<Int(40 * scale) {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                peakBlue = max(peakBlue, color.blueComponent)
            }
        }
        XCTAssertGreaterThan(peakBlue, 0.7, "阶段图标不应因两个遮罩交叉淡出而变暗")
    }

    func testExportPhaseStateBoardWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOX_ISLAND_RENDER_DIR"] else { return }
        var snapshots: [NSBitmapImageRep] = []
        for status in RecorderStatus.allCases {
            snapshots.append(try await render(status: status, transcript: status == .idle ? "" : "明天开会讨论下一步计划。",
                                              placement: Self.notchedPlacement))
        }
        let canvas = NSImage(size: NSSize(width: 1040, height: 640))
        canvas.lockFocus()
        NSColor(QuickRecordingColors.neutrals.bg).setFill()
        NSRect(x: 0, y: 0, width: 1040, height: 640).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor(QuickRecordingColors.neutrals.text2)
        ]
        ("阶段色 · 与主界面同源" as NSString).draw(at: NSPoint(x: 24, y: 610), withAttributes: attributes)
        let labels = ["待命 · 蓝灰", "录音 · 青绿", "转写 · 雾蓝", "润色 · 薰衣草紫", "完成 · 柔绿", "错误 · 珊瑚红"]
        for (index, bitmap) in snapshots.enumerated() {
            let x = CGFloat(24 + (index % 2) * 512)
            let y = CGFloat(430 - (index / 2) * 188)
            NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: bitmap.size)
                .draw(in: NSRect(x: x, y: y, width: 480, height: 148))
            (labels[index] as NSString).draw(at: NSPoint(x: x, y: y + 154), withAttributes: attributes)
        }
        canvas.unlockFocus()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(canvas.tiffRepresentation)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory).appendingPathComponent("phase-board.png")
        try await Task.detached { try png.write(to: url) }.value
    }

    func testPhaseTransitionPreservesVisibleTextAndFixedFrame() async throws {
        let bitmap = try await render(status: .refining, transcript: "Visible transcript sample.",
                                      initialStatus: .listening, updateWait: .milliseconds(120),
                                      initialWait: .milliseconds(1100))
        if let directory = ProcessInfo.processInfo.environment["VOX_ISLAND_RENDER_DIR"] {
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent("text-during-transition.png")
            try await Task.detached { try png.write(to: url) }.value
        }
        let words = try recognizedLines(bitmap).joined(separator: " ")
        XCTAssertTrue(words.contains("Visible transcript sample"), "Synthetic OCR: \(words)")
        XCTAssertEqual(bitmap.size, NSSize(width: QuickRecordingLayout.panelWidth, height: QuickRecordingLayout.panelHeight))
    }

    func testColorWashIsVisibleAndStageDependent() async throws {
        let recording = try await render(status: .listening, transcript: "Sample")
        let refining = try await render(status: .refining, transcript: "Sample")
        // 共享背景是二维光团，不再只有底部中点一条色带；比较无文字区域的多点。
        var distance: CGFloat = 0
        for fraction in [0.25, 0.5, 0.75] {
            let x = Int(Double(recording.pixelsWide) * fraction), y = recording.pixelsHigh - 16
            let first = try XCTUnwrap(recording.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            let second = try XCTUnwrap(refining.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            distance = max(distance, abs(first.redComponent - second.redComponent) + abs(first.greenComponent - second.greenComponent)
                           + abs(first.blueComponent - second.blueComponent))
            XCTAssertGreaterThan(first.alphaComponent, 0.95)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            XCTAssertLessThan(distance, 0.01, "辅助显示模式应关闭装饰柔光，使用相同实色底")
        } else {
            XCTAssertGreaterThan(distance, 0.04)
        }
    }

    func testExportPhaseTransitionAnimationWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOX_ISLAND_RENDER_DIR"] else { return }
        let stages: [RecorderStatus] = [.listening, .transcribing, .refining, .done, .error]
        let host = NSHostingView(rootView: QuickRecordingIslandView(status: .listening, transcript: "明天开会讨论下一步计划。",
                                                                  audioLevel: 0.6, placement: Self.notchedPlacement))
        let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 480, height: 148),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(800))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: directory).appendingPathComponent("phase-transitions.gif") as CFURL,
            UTType.gif.identifier as CFString, stages.count * 6, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for status in stages {
            host.rootView = QuickRecordingIslandView(status: status, transcript: "明天开会讨论下一步计划。",
                                                    audioLevel: 0.6, placement: Self.notchedPlacement)
            for (index, delay) in [0, 120, 160, 200, 240, 240].enumerated() {
                try await Task.sleep(for: .milliseconds(delay))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.cgImage),
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: index == 5 ? 0.6 : 0.14]] as CFDictionary)
                if index == 2 || index == 5 {
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let url = URL(fileURLWithPath: directory).appendingPathComponent("transition-\(status)-\(index).png")
                    try await Task.detached { try data.write(to: url) }.value
                }
            }
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testTextDoesNotAppearClippedDuringInitialExpansion() async throws {
        let entrance = try await render(status: .listening, transcript: "New words visible.", initialWait: .milliseconds(100))
        let expansion = try await render(status: .listening, transcript: "New words visible.",
                                         initialTranscript: "", updateWait: .milliseconds(60))
        for early in [entrance, expansion] {
            let words = try recognizedLines(early).joined()
            XCTAssertEqual(words.contains("words"), NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                           "减少动态效果时不等待入场，正常动画时须等轮廓展开再显示文字")
        }
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
        try await Task.sleep(for: .milliseconds(800))
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
            let words = try recognizedLines(bitmap, languages: ["en-US", "zh-Hans"]).joined()
            for unwanted in ["正在", "准备", "实时", "松开", "取消", "00:"] {
                XCTAssertFalse(words.contains(unwanted), "\(status) contains unnecessary visible copy")
            }
        }
    }

    func testRenderedTranscriptIsVisibleOnlyInActiveStates() async throws {
        for status in RecorderStatus.allCases {
            // 此测试验证状态可见性，动画时序由独立入场与过渡测试覆盖。
            let bitmap = try await render(status: status, transcript: "Visible transcript sample.", reduceMotion: true)
            let words = try recognizedLines(bitmap).joined(separator: " ")
            XCTAssertEqual(words.contains("Visible transcript sample"), status != .idle,
                           "\(status) synthetic OCR \(bitmap.pixelsWide)x\(bitmap.pixelsHigh): \(words)")
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
        let words = try recognizedLines(bitmap).joined(separator: " ")
        XCTAssertTrue(words.contains("Latest sentence visible"))
        XCTAssertFalse(words.contains("First sentence"))
    }

    func testManualScrollIsPreservedWhenNewTextArrives() async throws {
        let original = "Oldest sentence visible.\n" + String(repeating: "Earlier recognized text.\n", count: 40)
        let bitmap = try await render(status: .listening, transcript: original + "Newest addition.",
                                      initialTranscript: original, scrollToTopBeforeUpdate: true)
        let words = try recognizedLines(bitmap).joined(separator: " ")
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
        initialStatus: RecorderStatus? = nil, updateWait: Duration = .milliseconds(450),
        initialWait: Duration = .milliseconds(800), reduceMotion: Bool = false,
        colorScheme: ColorScheme = .light
    ) async throws -> NSBitmapImageRep {
        let size = NSSize(width: QuickRecordingLayout.panelWidth, height: QuickRecordingLayout.panelHeight)
        let state = FakeIslandRenderState(status: initialStatus ?? status, transcript: initialTranscript ?? transcript)
        let host = NSHostingView(rootView: IslandRenderHost(state: state, placement: placement,
                                                          reduceMotion: reduceMotion, colorScheme: colorScheme))
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let mountDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !state.isMounted && ContinuousClock.now < mountDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(state.isMounted, "先确认原生宿主已挂载，再计算截图的动画采样时间")
        await Task.yield()
        try await Task.sleep(for: initialWait)
        if scrollToTopBeforeUpdate {
            let scroll = try XCTUnwrap(findScrollView(in: host))
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(100))
        }
        if initialTranscript != nil || initialStatus != nil {
            // 与真实 QuickRecordingView 一样更新可观察状态，不重建宿主根视图。
            state.status = status
            state.transcript = transcript
            try await Task.sleep(for: updateWait)
        }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    func testTextRecognitionWorksWithNonRetinaCapture() async throws {
        let bitmap = try await render(status: .listening, transcript: "Visible transcript sample.", reduceMotion: true)
        let image = try resample(XCTUnwrap(bitmap.cgImage), width: Int(QuickRecordingLayout.panelWidth))
        let oneX = NSBitmapImageRep(cgImage: image)
        XCTAssertTrue(try recognizedLines(oneX).joined(separator: " ").contains("Visible transcript sample"))
    }

    /// OCR 固定语言、sRGB 像素格式与至少 2x 输入；几何与透明区测试仍使用原始截图。
    private func recognizedLines(_ bitmap: NSBitmapImageRep, languages: [String] = ["en-US"]) throws -> [String] {
        let source = try XCTUnwrap(bitmap.cgImage)
        let image = try resample(source, width: max(source.width, Int(QuickRecordingLayout.panelWidth * 2)))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private func resample(_ image: CGImage, width: Int) throws -> CGImage {
        let height = max(1, Int(Double(image.height) * Double(width) / Double(image.width)))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }

    private func opaqueBounds(_ bitmap: NSBitmapImageRep) throws -> CGRect {
        var bounds = CGRect.null
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                bounds = bounds.union(CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale,
                                             width: 1 / scale, height: 1 / scale))
            }
        }
        XCTAssertFalse(bounds.isNull)
        return bounds
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

@MainActor
private final class FakeIslandRenderState: ObservableObject {
    @Published var status: RecorderStatus
    @Published var transcript: String
    @Published var isMounted = false

    init(status: RecorderStatus, transcript: String) {
        self.status = status
        self.transcript = transcript
    }
}

@MainActor
private struct IslandRenderHost: View {
    @ObservedObject var state: FakeIslandRenderState
    let placement: QuickRecordingPlacement
    let reduceMotion: Bool
    let colorScheme: ColorScheme

    var body: some View {
        QuickRecordingIslandView(status: state.status, transcript: state.transcript, audioLevel: 0.6,
                                 placement: placement, forceReducedMotion: reduceMotion)
            .environment(\.colorScheme, colorScheme)
            .onAppear { state.isMounted = true }
    }
}
#endif
