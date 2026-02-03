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

    static let light = Theme(
        palette: Palette(
            textPrimary: Color.black.opacity(0.9),
            textSecondary: Color.black.opacity(0.65),
            textTertiary: Color.black.opacity(0.45),
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
            title: .system(size: 22, weight: .semibold, design: .rounded),
            headline: .system(size: 17, weight: .semibold, design: .rounded),
            body: .system(size: 15, weight: .regular, design: .rounded),
            callout: .system(size: 13, weight: .medium, design: .rounded),
            caption: .system(size: 11, weight: .regular, design: .rounded)
        )
    )

    static let dark = Theme(
        palette: Palette(
            textPrimary: Color.white.opacity(0.96),
            textSecondary: Color.white.opacity(0.7),
            textTertiary: Color.white.opacity(0.5),
            surfaceGlass: Color.white.opacity(0.12),
            surfaceGlassStrong: Color.white.opacity(0.2),
            surfaceElevated: Color.white.opacity(0.16),
            strokeSubtle: Color.white.opacity(0.16),
            strokeStrong: Color.white.opacity(0.28),
            accentPrimary: Color(red: 0.44, green: 0.66, blue: 0.84),
            accentSecondary: Color(red: 0.52, green: 0.7, blue: 0.9),
            statusListening: Color(red: 0.42, green: 0.76, blue: 0.82),
            statusRefining: Color(red: 0.56, green: 0.54, blue: 0.88),
            statusDone: Color(red: 0.54, green: 0.8, blue: 0.62),
            statusError: Color(red: 0.8, green: 0.4, blue: 0.42),
            backgroundBase: Color(red: 0.06, green: 0.08, blue: 0.12),
            backgroundVignette: Color.black
        ),
        typography: Typography(
            title: .system(size: 22, weight: .semibold, design: .rounded),
            headline: .system(size: 17, weight: .semibold, design: .rounded),
            body: .system(size: 15, weight: .regular, design: .rounded),
            callout: .system(size: 13, weight: .medium, design: .rounded),
            caption: .system(size: 11, weight: .regular, design: .rounded)
        )
    )
}
