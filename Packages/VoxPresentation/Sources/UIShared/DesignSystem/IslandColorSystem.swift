#if os(macOS)
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// ============================================================================
//  ColorSystem — the seed color system, shared verbatim with the web port
//  (design-system/templates/shared/color-system.ts) and with the
//  visual-design-modernization skill's references/color-system.md.
//
//  ONE seed → the whole primary token set. Semantic colors are FIXED.
//  Neutrals come from Radix slate or Tailwind neutral. Never invent a 2nd set.
// ============================================================================

public extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Preset seeds (identical to the web port)

public enum Seed: String, CaseIterable, Sendable {
    case blue, purple, teal, orange, appleBlue

    public var hex: String {
        switch self {
        case .blue: return "#0090FF"
        case .purple: return "#8E4EC6"
        case .teal: return "#12A594"
        case .orange: return "#F76B15"
        case .appleBlue: return "#007AFF"
        }
    }

    public var color: Color { Color(hex: hex) }
}

// MARK: - Primary palette derivation

public struct PrimaryPalette: Sendable {
    public let primary, primaryHover, primaryActive: Color
    public let primarySubtle, primaryMuted, primaryBorder: Color
    public let primaryText, onPrimary, onPrimarySubtle, ring: Color
}

private func hsbComponents(_ c: Color) -> (h: Double, s: Double, b: Double) {
    #if canImport(AppKit)
    let ns = NSColor(c).usingColorSpace(.deviceRGB) ?? .black
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return (Double(h), Double(s), Double(b))
    #else
    return (0.58, 0.8, 0.9)
    #endif
}

public func hsbHue(_ c: Color) -> Double { hsbComponents(c).h }

private func relLuminance(_ c: Color) -> Double {
    #if canImport(AppKit)
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
    func lin(_ v: CGFloat) -> Double {
        let x = Double(v)
        return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(ns.redComponent) + 0.7152 * lin(ns.greenComponent) + 0.0722 * lin(ns.blueComponent)
    #else
    return 0.5
    #endif
}

private func contrastChoose(_ bg: Color) -> Color {
    let lum = relLuminance(bg)
    return (1.05 / (lum + 0.05)) >= ((lum + 0.05) / 0.05) ? .white : .black
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

/// One seed → the whole primary token set. Same math as the web `makePrimaryPalette`.
public func makePrimaryPalette(seed: Color, isDark: Bool) -> PrimaryPalette {
    let (h, s, b) = hsbComponents(seed)
    func c(_ hh: Double, _ ss: Double, _ bb: Double) -> Color {
        Color(hue: hh, saturation: clamp(ss), brightness: clamp(bb))
    }
    if isDark {
        let primary = c(h, s - 0.05, b + 0.06)
        return PrimaryPalette(
            primary: primary,
            primaryHover: c(h, s, b + 0.08),
            primaryActive: c(h, s, b + 0.14),
            primarySubtle: c(h, s * 0.45, 0.18),
            primaryMuted: c(h, s * 0.50, 0.26),
            primaryBorder: c(h, s * 0.55, 0.36),
            primaryText: c(h, s * 0.70, b + 0.28),
            onPrimary: contrastChoose(primary),
            onPrimarySubtle: c(h, s * 0.70, b + 0.28),
            ring: primary.opacity(0.65)
        )
    } else {
        let primary = seed
        return PrimaryPalette(
            primary: primary,
            primaryHover: c(h, s, b - 0.08),
            primaryActive: c(h, s, b - 0.14),
            primarySubtle: c(h, s * 0.18, 0.97),
            primaryMuted: c(h, s * 0.40, 0.90),
            primaryBorder: c(h, s * 0.55, 0.80),
            primaryText: c(h, min(1, s + 0.10), b - 0.20),
            onPrimary: contrastChoose(primary),
            onPrimarySubtle: c(h, min(1, s + 0.10), b - 0.20),
            ring: primary.opacity(0.55)
        )
    }
}

/// On-brand chart palette — walk the hue wheel from the seed (same offsets as web).
public func chartPalette(seed: Color, isDark: Bool) -> [Color] {
    let seedHue = hsbHue(seed) * 360
    let offsets: [Double] = [0, -15, 40, 95, 130, 175, -70, 210]
    return offsets.map { off in
        let h = (((seedHue + off).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)) / 360
        return isDark
            ? Color(hue: h, saturation: 0.66, brightness: 0.82)
            : Color(hue: h, saturation: 0.72, brightness: 0.62)
    }
}

// MARK: - Neutral palettes (fixed hex)

public struct Neutrals: Sendable {
    public let bg, card, inner, text1, text2, text3, border: Color
}

public enum Neutral: String, CaseIterable, Sendable {
    case slate, neutral

    public func palette(isDark: Bool) -> Neutrals {
        switch (self, isDark) {
        case (.slate, false):
            return Neutrals(bg: Color(hex: "#F9F9FB"), card: Color(hex: "#FFFFFF"), inner: Color(hex: "#F0F0F3"),
                            text1: Color(hex: "#1C2024"), text2: Color(hex: "#60646C"), text3: Color(hex: "#80838D"),
                            border: Color(hex: "#D9D9E0"))
        case (.slate, true):
            return Neutrals(bg: Color(hex: "#111113"), card: Color(hex: "#18191B"), inner: Color(hex: "#212225"),
                            text1: Color(hex: "#EDEEF0"), text2: Color(hex: "#B0B4BA"), text3: Color(hex: "#777B84"),
                            border: Color(hex: "#363A3F"))
        case (.neutral, false):
            return Neutrals(bg: Color(hex: "#FAFAFA"), card: Color(hex: "#FFFFFF"), inner: Color(hex: "#F5F5F5"),
                            text1: Color(hex: "#171717"), text2: Color(hex: "#525252"), text3: Color(hex: "#737373"),
                            border: Color(hex: "#E5E5E5"))
        case (.neutral, true):
            return Neutrals(bg: Color(hex: "#171717"), card: Color(hex: "#262626"), inner: Color(hex: "#2E2E2E"),
                            text1: Color(hex: "#FAFAFA"), text2: Color(hex: "#A3A3A3"), text3: Color(hex: "#737373"),
                            border: Color(hex: "#404040"))
        }
    }
}

// MARK: - Semantic colors (FIXED — never seed-derived)

public enum Semantic {
    public static func success(isDark: Bool) -> Color { Color(hex: isDark ? "#30D158" : "#34C759") }
    public static func warning(isDark: Bool) -> Color { Color(hex: isDark ? "#FF9F0A" : "#FF9500") }
    public static func danger(isDark: Bool) -> Color { Color(hex: isDark ? "#FF453A" : "#FF3B30") }
}
#endif
