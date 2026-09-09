#if os(macOS)
import SwiftUI

/// 浮窗与主 UI 共用外观和阶段色；图标按外观派生可读前景，不另建阶段色库。
public enum QuickRecordingColors {
    public static var neutrals: Neutrals { neutrals(for: .light) }
    public static var primary: PrimaryPalette { primary(for: .light) }
    public static let success = AtmosphereGlass.colors(for: .done)[0]
    public static let danger = AtmosphereGlass.colors(for: .error)[0]
    public static let transcribing = AtmosphereGlass.colors(for: .transcribing)[0]
    public static let refining = AtmosphereGlass.colors(for: .refining)[0]
    public static let transitionDuration = AtmosphereGlass.transitionDuration

    public static func neutrals(for scheme: ColorScheme) -> Neutrals {
        Neutral.slate.palette(isDark: scheme == .dark)
    }

    public static func primary(for scheme: ColorScheme) -> PrimaryPalette {
        makePrimaryPalette(seed: Theme.current(scheme).palette.accentPrimary, isDark: scheme == .dark)
    }

    public static func background(for scheme: ColorScheme) -> Color {
        AtmosphereGlass.baseColor(for: scheme)
    }

    public static func status(_ status: RecorderStatus, colorScheme: ColorScheme = .light) -> Color {
        guard status != .idle else { return neutrals(for: colorScheme).text1 }
        let seed = AtmosphereGlass.colors(for: status)[0]
        guard colorScheme == .light else { return seed }
        let (hue, saturation, brightness) = hsbComponents(seed)
        return Color(hue: hue, saturation: min(1, saturation + 0.1), brightness: brightness * 0.45)
    }

    /// 取主 UI 的左上、色心与右上光团，缩成浮窗的横向柔光。
    public static func atmosphere(_ status: RecorderStatus) -> [Color] {
        let colors = AtmosphereGlass.colors(for: status)
        return [colors[0], colors[4], colors[1]]
    }

    public static func rim(_ status: RecorderStatus, colorScheme: ColorScheme = .light) -> [Color] {
        let colors = atmosphere(status)
        let strength = status == .idle ? 0.16 : 0.56
        return [colors[0].opacity(strength), neutrals(for: colorScheme).border.opacity(0.7), colors[2].opacity(strength), colors[1].opacity(strength)]
    }

    public static func energy(status: RecorderStatus, audioLevel: Double?) -> Double {
        guard status == .listening, let audioLevel, audioLevel.isFinite else { return 0 }
        return min(1, max(0, audioLevel))
    }

    public static func allowsAtmosphere(reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
        AtmosphereGlass.allowsAtmosphere(reduceTransparency: reduceTransparency, increasedContrast: increasedContrast)
    }
}
#endif
