import SwiftUI

enum WatchTheme {
    struct Palette {
        let canvas: Color
        let primaryText: Color
        let secondaryText: Color
        let cardBackground: Color
    }
    static let cyan = Color("WatchCyan")
    static let coral = Color("WatchCoral")
    static let solidGlyph = Color("WatchInkDark")

    // watchOS 不可靠地解析 luminosity 变体，也不会为强制浅色预览调整系统文字颜色。
    static func palette(for scheme: ColorScheme) -> Palette {
        if scheme == .light {
            return Palette(canvas: Color("WatchCanvasLight"), primaryText: Color("WatchInkDark"),
                           secondaryText: Color("WatchInkSecondaryLight"), cardBackground: Color("WatchCardLight"))
        }
        return Palette(canvas: Color("WatchCanvas"), primaryText: Color("WatchInkLight"),
                       secondaryText: Color("WatchInkSecondaryDark"), cardBackground: Color("WatchCardDark"))
    }
}
