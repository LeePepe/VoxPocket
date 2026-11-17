import SwiftUI
import CoreModels
import UIShared
#if os(macOS)
import AppKit
import AVFoundation
import CoreVideo
#endif

@main
struct VoxTodoPreviewHostEntry {
    @MainActor
    static func main() {
        #if os(macOS)
        let args = CommandLine.arguments
        if let exportIdx = args.firstIndex(of: "--export-gallery"), exportIdx + 1 < args.count {
            let outputDir = args[exportIdx + 1]
            let code = GalleryFrameExporter.exportAll(to: URL(fileURLWithPath: outputDir))
            exit(code)
        }
        if let encodeIdx = args.firstIndex(of: "--encode-videos"), encodeIdx + 1 < args.count {
            let outputDir = args[encodeIdx + 1]
            let code = GalleryFrameExporter.encodeVideosFromExistingFrames(at: URL(fileURLWithPath: outputDir))
            exit(code)
        }
        if let snapshotIdx = args.firstIndex(of: "--snapshot-board"), snapshotIdx + 1 < args.count {
            let outputFile = args[snapshotIdx + 1]
            let code = GalleryFrameExporter.exportBoardSnapshot(to: URL(fileURLWithPath: outputFile))
            exit(code)
        }

        let app = NSApplication.shared
        let delegate = PreviewHostAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        #endif
    }
}

#if os(macOS)
@MainActor
final class PreviewHostAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let boardView = TodoUnfoldFourUpPreviewBoard()
        let hostingView = NSHostingView(rootView: boardView)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1720, height: 1000)
        let width = min(1720, max(1280, screenFrame.width - 24))
        let height = min(980, max(780, screenFrame.height - 24))
        let rect = NSRect(
            x: screenFrame.minX + (screenFrame.width - width) / 2,
            y: screenFrame.minY + (screenFrame.height - height) / 2,
            width: width,
            height: height
        )

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoxPocket · Todo 卡片原地展开 4 套真 SwiftUI 交互预览窗 (v01–v04 · 120Hz Native)"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let autoShotPath = ProcessInfo.processInfo.environment["VOX_PREVIEW_AUTOSHOT"], !autoShotPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                _ = GalleryFrameExporter.captureViewPNG(hostingView, to: URL(fileURLWithPath: autoShotPath))
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
enum GalleryFrameExporter {
    static func exportBoardSnapshot(to outputURL: URL) -> Int32 {
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let board = TodoUnfoldFourUpPreviewBoard()
            .environment(\.colorScheme, .dark)
            .frame(width: 1680, height: 980)
        let host = NSHostingView(rootView: board)
        host.frame = NSRect(x: 0, y: 0, width: 1680, height: 980)
        let panel = NSPanel(
            contentRect: NSRect(x: -10000, y: -10000, width: 1680, height: 980),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return captureViewPNG(host, to: outputURL) ? 0 : 1
    }

    static func exportAll(to baseDir: URL) -> Int32 {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        // Export a full 4-up board snapshot first
        let boardSnapURL = baseDir.appendingPathComponent("four-up-board-dark.png")
        _ = exportBoardSnapshot(to: boardSnapURL)

        let schemes: [(name: String, scheme: ColorScheme, appearance: NSAppearance.Name)] = [
            ("dark", .dark, .darkAqua),
            ("light", .light, .aqua)
        ]

        for variant in TodoUnfoldVariantKind.allCases {
            for mode in schemes {
                let variantDir = baseDir
                    .appendingPathComponent("frames", isDirectory: true)
                    .appendingPathComponent("\(variant.rawValue)-\(mode.name)", isDirectory: true)
                try? fm.createDirectory(at: variantDir, withIntermediateDirectories: true)

                let keyframesDir = baseDir
                    .appendingPathComponent("keyframes", isDirectory: true)
                try? fm.createDirectory(at: keyframesDir, withIntermediateDirectories: true)

                // Keyframes: collapsed, expanded, tag-tray
                exportSingleState(
                    variant: variant,
                    scheme: mode.scheme,
                    appearanceName: mode.appearance,
                    expanded: false,
                    tagTrayOpen: false,
                    interpolation: 0.0,
                    to: keyframesDir.appendingPathComponent("\(variant.rawValue)-\(mode.name)-collapsed.png")
                )
                exportSingleState(
                    variant: variant,
                    scheme: mode.scheme,
                    appearanceName: mode.appearance,
                    expanded: true,
                    tagTrayOpen: false,
                    interpolation: 1.0,
                    to: keyframesDir.appendingPathComponent("\(variant.rawValue)-\(mode.name)-expanded.png")
                )
                exportSingleState(
                    variant: variant,
                    scheme: mode.scheme,
                    appearanceName: mode.appearance,
                    expanded: true,
                    tagTrayOpen: true,
                    interpolation: 1.0,
                    to: keyframesDir.appendingPathComponent("\(variant.rawValue)-\(mode.name)-tagtray.png")
                )

                // Export 90 frames (1.5s @ 60fps):
                // Frames 0..11: collapsed hold
                // Frames 12..35: spring unfold (0.0 -> 1.0)
                // Frames 36..51: expanded hold
                // Frames 52..67: tag tray open hold
                // Frames 68..83: spring collapse (1.0 -> 0.0)
                // Frames 84..89: collapsed hold
                let totalFrames = 90
                for frameIdx in 0..<totalFrames {
                    let (progress, tagTray) = choreographyState(for: variant, frame: frameIdx)
                    let frameURL = variantDir.appendingPathComponent(String(format: "frame_%03d.png", frameIdx))
                    exportSingleState(
                        variant: variant,
                        scheme: mode.scheme,
                        appearanceName: mode.appearance,
                        expanded: progress > 0.005,
                        tagTrayOpen: tagTray,
                        interpolation: progress,
                        to: frameURL
                    )
                }
            }
        }
        _ = encodeVideosFromExistingFrames(at: baseDir)
        return 0
    }

    static func encodeVideosFromExistingFrames(at baseDir: URL) -> Int32 {
        let videosDir = baseDir.appendingPathComponent("videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)

        for variant in TodoUnfoldVariantKind.allCases {
            for modeName in ["dark", "light"] {
                let framesDir = baseDir
                    .appendingPathComponent("frames", isDirectory: true)
                    .appendingPathComponent("\(variant.rawValue)-\(modeName)", isDirectory: true)
                let mp4URL = videosDir.appendingPathComponent("\(variant.rawValue)-\(modeName).mp4")
                _ = encodeFrameSequenceToMP4(framesDir: framesDir, frameCount: 90, fps: 60, outputURL: mp4URL)
            }
        }
        return 0
    }

    private static func encodeFrameSequenceToMP4(
        framesDir: URL,
        frameCount: Int,
        fps: Int32,
        outputURL: URL
    ) -> Bool {
        try? FileManager.default.removeItem(at: outputURL)
        let firstFrameURL = framesDir.appendingPathComponent("frame_000.png")
        guard let firstImage = NSImage(contentsOf: firstFrameURL),
              let firstCG = firstImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        let width = firstCG.width
        let height = firstCG.height

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            return false
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourceBufferAttributes
        )

        guard writer.canAdd(writerInput) else { return false }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for idx in 0..<frameCount {
            while !writerInput.isReadyForMoreMediaData {
                RunLoop.current.run(until: Date().addingTimeInterval(0.002))
            }
            let frameURL = framesDir.appendingPathComponent(String(format: "frame_%03d.png", idx))
            guard let img = NSImage(contentsOf: frameURL),
                  let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let pixelBuffer = makePixelBuffer(from: cgImg, width: width, height: height) else {
                continue
            }
            let presentationTime = CMTime(value: CMTimeValue(idx), timescale: fps)
            _ = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()
        return writer.status == .completed
    }

    private static func makePixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private static func choreographyState(for variant: TodoUnfoldVariantKind, frame: Int) -> (Double, Bool) {
        if frame < 12 {
            return (0.0, false)
        } else if frame < 36 {
            let t = Double(frame - 12) / 24.0
            return (springCurve(t, variant: variant), false)
        } else if frame < 52 {
            return (1.0, false)
        } else if frame < 68 {
            return (1.0, true)
        } else if frame < 84 {
            let t = Double(frame - 68) / 16.0
            return (max(0.0, 1.0 - springCurve(t, variant: variant)), false)
        } else {
            return (0.0, false)
        }
    }

    private static func springCurve(_ t: Double, variant: TodoUnfoldVariantKind) -> Double {
        let clamped = min(1.0, max(0.0, t))
        switch variant {
        case .v01:
            return 1.0 - pow(1.0 - clamped, 3.2)
        case .v02:
            return 1.0 - pow(1.0 - clamped, 3.8)
        case .v03:
            let base = 1.0 - exp(-5.2 * clamped) * cos(4.2 * clamped)
            return min(1.0, max(0.0, base))
        case .v04:
            return clamped < 0.5
                ? 4.0 * clamped * clamped * clamped
                : 1.0 - pow(-2.0 * clamped + 2.0, 3.0) / 2.0
        }
    }

    private static func exportSingleState(
        variant: TodoUnfoldVariantKind,
        scheme: ColorScheme,
        appearanceName: NSAppearance.Name,
        expanded: Bool,
        tagTrayOpen: Bool,
        interpolation: Double,
        to url: URL
    ) {
        let store = TodoUnfoldVariantPreviewStore(
            variant: variant,
            initiallyExpanded: expanded,
            initiallyTagTrayOpen: tagTrayOpen
        )
        let view = TodoUnfoldVariantPhoneViewport(
            store: store,
            interpolationProgress: interpolation
        )
        .environment(\.colorScheme, scheme)
        .frame(width: 390, height: 844)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 390, height: 844)
        let panel = NSPanel(
            contentRect: NSRect(x: -10000, y: -10000, width: 390, height: 844),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: appearanceName)
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        host.layoutSubtreeIfNeeded()
        _ = captureViewPNG(host, to: url)
    }

    static func captureViewPNG(_ view: NSView, to url: URL) -> Bool {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return false
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
#endif
