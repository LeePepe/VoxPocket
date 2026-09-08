#if os(macOS)
import CoreGraphics
import UIShared

/// 屏幕几何是值对象；AppKit 仅负责提供真实屏幕与刘海矩形。
public struct QuickRecordingPlacement: Equatable, Sendable {
    public let panelFrame: CGRect
    public let cameraSize: CGSize
    public var isAttached: Bool { cameraSize.height > 0 }

    public init(screenFrame: CGRect, visibleFrame: CGRect, cameraRect: CGRect? = nil) {
        let camera = cameraRect?.intersection(screenFrame) ?? .null
        let attached = !camera.isNull && camera.width > 0 && camera.height > 0
            && camera.width + QuickRecordingLayout.cameraWingSpace <= min(QuickRecordingLayout.panelWidth, screenFrame.width - 32)
        let available = attached ? screenFrame : visibleFrame
        let width = min(QuickRecordingLayout.panelWidth, max(1, available.width - 32))
        let height = min(QuickRecordingLayout.panelHeight, max(1, available.height - 24))
        let center = attached ? camera.midX : available.midX
        let x = min(max(center - width / 2, available.minX + 16), available.maxX - width - 16)
        let top = attached ? screenFrame.maxY : visibleFrame.maxY - QuickRecordingLayout.topInset
        panelFrame = CGRect(x: x, y: max(available.minY, top - height), width: width, height: height)
        cameraSize = attached ? camera.size : .zero
    }

    /// 无真实屏幕信息时仅用于独立预览，不虚构刘海。
    public static let floating = QuickRecordingPlacement(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
}

public enum QuickRecordingLayout {
    public static let panelWidth: CGFloat = 480
    public static let panelHeight: CGFloat = 148
    public static let topInset: CGFloat = 12
    public static let headerHeight: CGFloat = 52
    public static let readingHeight: CGFloat = 80
    public static let waveformWidth: CGFloat = 42
    public static let contentInset: CGFloat = 24
    public static let cameraWingSpace: CGFloat = 144

    public static func islandSize(for status: RecorderStatus, showsTranscript: Bool = false,
                                  textHeight: CGFloat = readingHeight) -> CGSize {
        if showsTranscript && status != .idle {
            // 展开只发生一次；后续识别和润色更新不再触发测高 → 二次伸缩。
            return CGSize(width: panelWidth, height: panelHeight)
        }
        return CGSize(width: 280, height: headerHeight)
    }

    public static func islandCorner(for status: RecorderStatus) -> CGFloat { 24 }

    /// 留足两翼，即使等待态收窄也不让文字侵入硬件区域。
    public static func size(for status: RecorderStatus, showsTranscript: Bool, placement: QuickRecordingPlacement,
                            textHeight: CGFloat = readingHeight) -> CGSize {
        let desired = islandSize(for: status, showsTranscript: showsTranscript, textHeight: textHeight)
        let safeWidth = placement.isAttached ? placement.cameraSize.width + cameraWingSpace : 0
        return CGSize(width: min(max(desired.width, safeWidth), placement.panelFrame.width),
                      height: min(desired.height, placement.panelFrame.height))
    }
}
#endif
