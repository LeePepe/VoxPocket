// VoxScreenCapture.swift
// VoxPocket 截图采集器
// macOS：使用 ScreenCaptureKit；iOS：使用 UIGraphicsImageRenderer

import Foundation
import CoreGraphics

#if os(macOS)
import ScreenCaptureKit
import AppKit
#else
import UIKit
#endif

// MARK: - 截图错误

public enum VoxScreenCaptureError: Error, Sendable {
    /// 无法枚举可共享内容
    case noShareableContent
    /// 未找到目标窗口
    case windowNotFound
    /// 截图失败（底层错误）
    case captureFailed(String)
    /// 平台不支持
    case unsupportedPlatform
}

// MARK: - 截图结果

/// 截图结果：包含原始 CGImage 与元数据
public struct CapturedFrame: Sendable {
    /// 截图 CGImage
    public let image: CGImage
    /// 捕获时间戳
    public let capturedAt: Date
    /// 源窗口标题（若可获取）
    public let windowTitle: String?

    public init(image: CGImage, capturedAt: Date = Date(), windowTitle: String? = nil) {
        self.image = image
        self.capturedAt = capturedAt
        self.windowTitle = windowTitle
    }

    /// 将 CGImage 编码为 PNG Data
    public func pngData() -> Data? {
        #if os(macOS)
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
        #else
        return UIImage(cgImage: image).pngData()
        #endif
    }
}

// MARK: - VoxScreenCapture

/// VoxPocket 截图采集门面
///
/// 使用示例 (macOS)：
/// ```swift
/// let frame = try await VoxScreenCapture.captureVoxPocket()
/// // frame.image → CGImage 可直接送入 VoxAgentEvaluator
/// ```
public enum VoxScreenCapture {

    // MARK: 主入口

    /// 捕获 VoxPocket 应用的前台窗口截图
    ///
    /// - Parameter appBundleID: 目标 Bundle ID，默认 VoxPocket
    /// - Returns: `CapturedFrame`
    public static func captureVoxPocket(
        appBundleID: String = "com.tianpeili.VoxPocket"
    ) async throws -> CapturedFrame {
        #if os(macOS)
        return try await captureWindow(bundleID: appBundleID)
        #else
        return try await captureScreen()
        #endif
    }

    /// 将整个主屏幕截图（跨平台）
    public static func captureFullScreen() async throws -> CapturedFrame {
        #if os(macOS)
        return try await captureMainDisplay()
        #else
        return try await captureScreen()
        #endif
    }

    // MARK: macOS 实现 (ScreenCaptureKit)

    #if os(macOS)
    /// 捕获指定 Bundle ID 的应用窗口
    private static func captureWindow(bundleID: String) async throws -> CapturedFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // 找到目标应用
        guard let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }) else {
            throw VoxScreenCaptureError.windowNotFound
        }

        // 选取第一个可见窗口
        let appWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID }
        guard let window = appWindows.first else {
            throw VoxScreenCaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width  = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.scalesToFit = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CapturedFrame(image: image, windowTitle: window.title)
    }

    /// 捕获主显示器全屏
    private static func captureMainDisplay() async throws -> CapturedFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw VoxScreenCaptureError.noShareableContent
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width  = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CapturedFrame(image: image, windowTitle: "MainDisplay")
    }
    #endif

    // MARK: iOS 实现 (UIGraphicsImageRenderer)

    #if os(iOS)
    /// iOS：对主窗口进行截图
    private static func captureScreen() async throws -> CapturedFrame {
        return try await MainActor.run {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) else {
                throw VoxScreenCaptureError.windowNotFound
            }

            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { ctx in
                window.layer.render(in: ctx.cgContext)
            }

            guard let cgImage = image.cgImage else {
                throw VoxScreenCaptureError.captureFailed("UIImage → CGImage 转换失败")
            }

            return CapturedFrame(image: cgImage, windowTitle: "iOSKeyWindow")
        }
    }
    #endif

    #if !os(macOS) && !os(iOS)
    private static func captureScreen() async throws -> CapturedFrame {
        throw VoxScreenCaptureError.unsupportedPlatform
    }
    #endif
}
