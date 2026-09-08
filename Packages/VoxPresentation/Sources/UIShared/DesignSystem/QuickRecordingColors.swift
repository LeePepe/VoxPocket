#if os(macOS)
import SwiftUI

/// 「声音落岛」沿用 my-designer 的 blue / slate；语义色不随主色变化。
public enum QuickRecordingColors {
    public static let neutrals = Neutral.slate.palette(isDark: true)
    public static let primary = makePrimaryPalette(seed: Seed.blue.color, isDark: true)
    public static let success = Semantic.success(isDark: true)
    public static let danger = Semantic.danger(isDark: true)
    /// 用户选择状态色语言；这些固定语义强调色不改变全局 blue 品牌主题。
    public static let transcribing = makePrimaryPalette(seed: Seed.teal.color, isDark: true).primaryText
    public static let refining = makePrimaryPalette(seed: Seed.purple.color, isDark: true).primaryText

    public static func status(_ status: RecorderStatus) -> Color {
        switch status {
        case .idle: neutrals.text2
        case .listening: primary.primaryText
        case .transcribing: transcribing
        case .refining: refining
        case .done: success
        case .error: danger
        }
    }
}
#endif
