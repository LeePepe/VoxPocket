import SwiftUI

enum ColorToken {
    case textPrimary
    case textSecondary
    case textTertiary
    case surfaceGlass
    case surfaceGlassStrong
    case surfaceElevated
    case strokeSubtle
    case strokeStrong
    case accentPrimary
    case accentSecondary
    case statusListening
    case statusRefining
    case statusDone
    case statusError
    case backgroundBase
    case backgroundVignette
}

enum FontToken {
    case title
    case headline
    case body
    case callout
    case caption
}

struct Theme {
    struct Palette {
        let textPrimary: Color
        let textSecondary: Color
        let textTertiary: Color
        let surfaceGlass: Color
        let surfaceGlassStrong: Color
        let surfaceElevated: Color
        let strokeSubtle: Color
        let strokeStrong: Color
        let accentPrimary: Color
        let accentSecondary: Color
        let statusListening: Color
        let statusRefining: Color
        let statusDone: Color
        let statusError: Color
        let backgroundBase: Color
        let backgroundVignette: Color

        func resolve(_ token: ColorToken) -> Color {
            switch token {
            case .textPrimary: return textPrimary
            case .textSecondary: return textSecondary
            case .textTertiary: return textTertiary
            case .surfaceGlass: return surfaceGlass
            case .surfaceGlassStrong: return surfaceGlassStrong
            case .surfaceElevated: return surfaceElevated
            case .strokeSubtle: return strokeSubtle
            case .strokeStrong: return strokeStrong
            case .accentPrimary: return accentPrimary
            case .accentSecondary: return accentSecondary
            case .statusListening: return statusListening
            case .statusRefining: return statusRefining
            case .statusDone: return statusDone
            case .statusError: return statusError
            case .backgroundBase: return backgroundBase
            case .backgroundVignette: return backgroundVignette
            }
        }
    }

    struct Typography {
        let title: Font
        let headline: Font
        let body: Font
        let callout: Font
        let caption: Font

        func resolve(_ token: FontToken) -> Font {
            switch token {
            case .title: return title
            case .headline: return headline
            case .body: return body
            case .callout: return callout
            case .caption: return caption
            }
        }
    }

    let palette: Palette
    let typography: Typography

    static func current(_ scheme: ColorScheme) -> Theme {
        scheme == .dark ? .dark : .light
    }

    // MARK: - Empty (typography-only) default

    /// Environment 未注入时的兜底主题。配色取 light，字体两套主题一致，
    /// 故仅依赖 typography 的子树（如 Snackbar）即便读到兜底值也表现正确。
    static let fallback = Theme.light

    static let light = Theme(
        palette: Palette(
            textPrimary: Color.black.opacity(0.9),
            textSecondary: Color.black.opacity(0.65),
            textTertiary: Color.black.opacity(0.58),
            surfaceGlass: Color.white.opacity(0.7),
            surfaceGlassStrong: Color.white.opacity(0.82),
            surfaceElevated: Color.white.opacity(0.9),
            strokeSubtle: Color.black.opacity(0.08),
            strokeStrong: Color.black.opacity(0.16),
            accentPrimary: Color(red: 0.22, green: 0.42, blue: 0.62),
            accentSecondary: Color(red: 0.3, green: 0.48, blue: 0.72),
            statusListening: Color(red: 0.22, green: 0.54, blue: 0.62),
            statusRefining: Color(red: 0.38, green: 0.36, blue: 0.68),
            statusDone: Color(red: 0.3, green: 0.58, blue: 0.42),
            statusError: Color(red: 0.68, green: 0.26, blue: 0.28),
            backgroundBase: Color(red: 0.92, green: 0.94, blue: 0.97),
            backgroundVignette: Color.black
        ),
        typography: Typography(
            title: .system(.title2, design: .rounded).weight(.semibold),
            headline: .system(.headline, design: .rounded),
            body: .system(.body, design: .rounded),
            callout: .system(.subheadline, design: .rounded).weight(.medium),
            caption: .system(.caption, design: .rounded)
        )
    )

    static let dark = Theme(
        palette: Palette(
            textPrimary: Color.white.opacity(0.96),
            textSecondary: Color.white.opacity(0.7),
            textTertiary: Color.white.opacity(0.62),
            surfaceGlass: Color.white.opacity(0.12),
            surfaceGlassStrong: Color.white.opacity(0.2),
            surfaceElevated: Color.white.opacity(0.16),
            strokeSubtle: Color.white.opacity(0.16),
            strokeStrong: Color.white.opacity(0.28),
            accentPrimary: Color(red: 0.36, green: 0.56, blue: 0.76),
            accentSecondary: Color(red: 0.44, green: 0.62, blue: 0.82),
            statusListening: Color(red: 0.28, green: 0.58, blue: 0.66),
            statusRefining: Color(red: 0.44, green: 0.42, blue: 0.72),
            statusDone: Color(red: 0.36, green: 0.60, blue: 0.46),
            statusError: Color(red: 0.66, green: 0.30, blue: 0.32),
            backgroundBase: Color(red: 0.06, green: 0.08, blue: 0.12),
            backgroundVignette: Color.black
        ),
        typography: Typography(
            title: .system(.title2, design: .rounded).weight(.semibold),
            headline: .system(.headline, design: .rounded),
            body: .system(.body, design: .rounded),
            callout: .system(.subheadline, design: .rounded).weight(.medium),
            caption: .system(.caption, design: .rounded)
        )
    )
}

// MARK: - Environment 注入

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = .fallback
}

extension EnvironmentValues {
    /// 当前主题。由根视图的 `.voxTheme()` 按 `colorScheme` 注入一次，下游直接读取，
    /// 避免每个节点重复 `Theme.current(colorScheme)` 并各自订阅 colorScheme。
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

private struct ThemeInjectionModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.theme, Theme.current(colorScheme))
    }
}

extension View {
    /// 在窗口根部注入随 `colorScheme` 解析出的主题。整棵子树共享同一个 `Theme` 实例，
    /// 仅此处订阅 colorScheme；切换深浅色时统一在根部重算并向下传播。
    func voxTheme() -> some View {
        modifier(ThemeInjectionModifier())
    }
}
