import SwiftUI

/// 恒亮玻璃面上的墨色语义色。
///
/// 快捷录音岛所在的浮层背景恒为近白玻璃（`AtmosphereGlass.baseColor` +
/// `.ultraThinMaterial`），无论系统深浅色都不变。因此其上的文字/描边**必须**用深墨色
/// 才有对比度——过去用 `Color.white` 会在近白玻璃上几乎不可见。
///
/// 这里把「恒亮玻璃」所需的语义色暴露为跨模块可用的公开常量，取值与 `Theme.light`
/// **单一同源**，不另起一套配色（遵守「一个设计语言、一个配色源」）。
public enum GlassInk {
    public static let textPrimary = Theme.light.palette.textPrimary
    public static let textSecondary = Theme.light.palette.textSecondary
    public static let textTertiary = Theme.light.palette.textTertiary
    public static let strokeSubtle = Theme.light.palette.strokeSubtle
    public static let strokeStrong = Theme.light.palette.strokeStrong

    /// 阶段强调色（描边点 / 波形着色）。语义固定：done 绿、error 珊瑚。
    public static func status(_ status: RecorderStatus) -> Color {
        switch status {
        case .listening, .transcribing:
            return Theme.light.palette.statusListening
        case .refining:
            return Theme.light.palette.statusRefining
        case .done:
            return Theme.light.palette.statusDone
        case .error:
            return Theme.light.palette.statusError
        case .idle:
            return Theme.light.palette.textTertiary
        }
    }
}
