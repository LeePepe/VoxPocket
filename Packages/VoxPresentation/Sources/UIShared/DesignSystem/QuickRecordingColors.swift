#if os(macOS)
import SwiftUI

/// 「声音落岛」沿用 my-designer 的 blue / slate；语义色不随主色变化。
public enum QuickRecordingColors {
    public static let neutrals = Neutral.slate.palette(isDark: true)
    public static let primary = makePrimaryPalette(seed: Seed.blue.color, isDark: true)
    public static let success = Semantic.success(isDark: true)
    public static let danger = Semantic.danger(isDark: true)
}
#endif
