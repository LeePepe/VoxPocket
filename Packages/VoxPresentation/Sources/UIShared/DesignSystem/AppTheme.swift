import SwiftUI

/// Per-App Brand & Spatial Tokens (Archetype: VS-003 × VS-005 / VoxPocket)
public enum AppTheme {
    // 1. 4pt Grid Scale (1:3:6 breathing ratio: xs=4, lg=16 card padding, xxl=24 section gap)
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let section: CGFloat = 32
    }

    // 2. Concentric Radii (innerRadius = max(4, outerRadius - padding))
    public enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
    }

    // 3. Semantic Brand & Surface Palette (Borderless Luminance Tiers: L0 < L1 < L2)
    public static let accent = Color.accentColor
    #if os(macOS)
    public static let surfacePrimary = Color(nsColor: .windowBackgroundColor)
    public static let surfaceCard = Color(nsColor: .controlBackgroundColor)
    public static let surfaceElevated = Color(nsColor: .underPageBackgroundColor)
    #else
    public static let surfacePrimary = Color(uiColor: .systemGroupedBackground)
    public static let surfaceCard = Color(uiColor: .secondarySystemGroupedBackground)
    public static let surfaceElevated = Color(uiColor: .tertiarySystemGroupedBackground)
    #endif

    // 4. Motion Signatures (Emil Kowalski frequency rule: 1.0 critically damped default)
    public static let snappySpring = Animation.spring(response: 0.26, dampingFraction: 1.0)
    public static let gestureSpring = Animation.spring(response: 0.32, dampingFraction: 0.80)
}

/// Consolidated Typography Modifier (at most 4 levels per viewport)
public struct AppTextStyle: ViewModifier {
    public enum Role { case heroMetric, sectionTitle, bodyPrimary, captionMeta }
    let role: Role

    public init(_ role: Role) { self.role = role }

    public func body(content: Content) -> some View {
        switch role {
        case .heroMetric:
            content.font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
        case .sectionTitle:
            content.font(.headline.bold())
        case .bodyPrimary:
            content.font(.body)
        case .captionMeta:
            content.font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

/// Signature Tactile ButtonStyle (micro-feedback press scale)
public struct AppPressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppTheme.snappySpring, value: configuration.isPressed)
    }
}
