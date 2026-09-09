#if os(macOS)
import SwiftUI

/// 深色浮窗直接消费主 UI 的 AtmosphereGlass 阶段色，不另建一套状态色库。
public enum QuickRecordingColors {
    public static let neutrals = Neutral.slate.palette(isDark: true)
    public static let primary = makePrimaryPalette(seed: Theme.dark.palette.accentPrimary, isDark: true)
    public static let success = AtmosphereGlass.colors(for: .done)[0]
    public static let danger = AtmosphereGlass.colors(for: .error)[0]
    public static let transcribing = AtmosphereGlass.colors(for: .transcribing)[0]
    public static let refining = AtmosphereGlass.colors(for: .refining)[0]
    public static let transitionDuration: TimeInterval = 0.72
    public static let leadingWashOpacity = 0.13
    public static let trailingWashOpacity = 0.09
    public static let baseRibbonOpacity = 0.22
    public static let audioRibbonBoost = 0.06

    public static func status(_ status: RecorderStatus) -> Color {
        status == .idle ? neutrals.text2 : AtmosphereGlass.colors(for: status)[0]
    }

    /// 取主 UI 的左上、色心与右上光团，缩成浮窗的横向柔光。
    public static func atmosphere(_ status: RecorderStatus) -> [Color] {
        let colors = AtmosphereGlass.colors(for: status)
        return [colors[0], colors[4], colors[1]]
    }

    public static func rim(_ status: RecorderStatus) -> [Color] {
        let colors = atmosphere(status)
        let strength = status == .idle ? 0.16 : 0.56
        return [colors[0].opacity(strength), neutrals.border.opacity(0.7), colors[2].opacity(strength), colors[1].opacity(strength)]
    }

    public static func energy(status: RecorderStatus, audioLevel: Double?) -> Double {
        guard status == .listening, let audioLevel, audioLevel.isFinite else { return 0 }
        return min(1, max(0, audioLevel))
    }

    public static func allowsAtmosphere(reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
        !reduceTransparency && !increasedContrast
    }
}
#endif
