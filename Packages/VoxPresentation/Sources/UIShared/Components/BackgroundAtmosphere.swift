import SwiftUI

public struct BackgroundAtmosphere: View {
    let status: RecorderStatus
    let audioLevel: Double?
    @State private var stateStart = Date()
    @Environment(\.colorScheme) private var colorScheme

    public init(status: RecorderStatus = .idle, audioLevel: Double? = nil) {
        self.status = status
        self.audioLevel = audioLevel
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(stateStart)
            let theme = Theme.current(colorScheme)
            let config = atmosphereConfig(for: status, elapsed: elapsed, audioLevel: audioLevel, theme: theme)

            ZStack {
                AtmospherePlate(config: config)
            }
            .ignoresSafeArea()
        }
        .onChange(of: status) { _, _ in
            stateStart = Date()
        }
    }

    private func atmosphereConfig(
        for status: RecorderStatus,
        elapsed: TimeInterval,
        audioLevel: Double?,
        theme: Theme
    ) -> AtmosphereConfig {
        let basePulse = slowPulse(elapsed: elapsed, period: 10)
        let baseColor = theme.palette.backgroundBase
        switch status {
        case .idle:
            return AtmosphereConfig(
                gradient: [
                    baseColor,
                    Color(red: 0.1, green: 0.14, blue: 0.2),
                    baseColor
                ],
                primaryShadow: Color(red: 0.2, green: 0.24, blue: 0.34),
                secondaryShadow: Color(red: 0.12, green: 0.16, blue: 0.24),
                primaryOpacity: 0.45 + basePulse * 0.08,
                secondaryOpacity: 0.35,
                primaryRadius: 26 + basePulse * 4,
                secondaryRadius: 18,
                primaryOffset: CGSize(width: 6, height: 8),
                secondaryOffset: CGSize(width: -4, height: -6),
                shadowLineWidth: 30,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.32
            )
        case .listening:
            let level = clamp(audioLevel ?? 0, min: 0, max: 1)
            let pulse = quickPulse(elapsed: elapsed, period: 0.9)
            let energy = max(level, pulse * 0.5)
            return AtmosphereConfig(
                gradient: [
                    baseColor,
                    Color(red: 0.04, green: 0.08, blue: 0.12),
                    baseColor
                ],
                primaryShadow: Color(red: 0.12, green: 0.42, blue: 0.46),
                secondaryShadow: Color(red: 0.08, green: 0.24, blue: 0.32),
                primaryOpacity: 0.55 + energy * 0.4,
                secondaryOpacity: 0.35 + energy * 0.2,
                primaryRadius: 26 + energy * 12,
                secondaryRadius: 18 + energy * 7,
                primaryOffset: CGSize(width: 6 + energy * 6, height: 8 + energy * 7),
                secondaryOffset: CGSize(width: -5 - energy * 4, height: -6 - energy * 5),
                shadowLineWidth: 32,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.55
            )
        case .transcribing:
            let breathe = slowPulse(elapsed: elapsed, period: 6.5)
            return AtmosphereConfig(
                gradient: [
                    baseColor,
                    Color(red: 0.09, green: 0.12, blue: 0.22),
                    baseColor
                ],
                primaryShadow: Color(red: 0.18, green: 0.28, blue: 0.56),
                secondaryShadow: Color(red: 0.12, green: 0.2, blue: 0.38),
                primaryOpacity: 0.5 + breathe * 0.18,
                secondaryOpacity: 0.34 + breathe * 0.1,
                primaryRadius: 24 + breathe * 8,
                secondaryRadius: 16 + breathe * 5,
                primaryOffset: CGSize(width: 6, height: 8),
                secondaryOffset: CGSize(width: -4, height: -6),
                shadowLineWidth: 30,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.45 + breathe * 0.08
            )
        case .refining:
            let pulse = slowPulse(elapsed: elapsed, period: 7.5)
            return AtmosphereConfig(
                gradient: [
                    baseColor,
                    Color(red: 0.14, green: 0.1, blue: 0.24),
                    baseColor
                ],
                primaryShadow: Color(red: 0.38, green: 0.24, blue: 0.6),
                secondaryShadow: Color(red: 0.24, green: 0.16, blue: 0.4),
                primaryOpacity: 0.52 + pulse * 0.16,
                secondaryOpacity: 0.36,
                primaryRadius: 26 + pulse * 6,
                secondaryRadius: 18,
                primaryOffset: CGSize(width: 6, height: 8),
                secondaryOffset: CGSize(width: -4, height: -6),
                shadowLineWidth: 32,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.5
            )
        case .done:
            let settle = doneSettle(elapsed: elapsed)
            return AtmosphereConfig(
                gradient: [
                    baseColor,
                    Color(red: 0.12, green: 0.2, blue: 0.18),
                    baseColor
                ],
                primaryShadow: Color(red: 0.22, green: 0.6, blue: 0.48),
                secondaryShadow: Color(red: 0.16, green: 0.34, blue: 0.3),
                primaryOpacity: 0.5 + settle.intensity,
                secondaryOpacity: 0.34,
                primaryRadius: 24 - settle.tighten,
                secondaryRadius: 16,
                primaryOffset: CGSize(width: 6, height: 8),
                secondaryOffset: CGSize(width: -4, height: -5),
                shadowLineWidth: 30,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.38
            )
        case .error:
            let jitter = Double(sin(elapsed * 6)) * 2
            return AtmosphereConfig(
                gradient: [
                    baseColor,
                    Color(red: 0.14, green: 0.06, blue: 0.12),
                    baseColor
                ],
                primaryShadow: Color(red: 0.52, green: 0.2, blue: 0.26),
                secondaryShadow: Color(red: 0.32, green: 0.12, blue: 0.18),
                primaryOpacity: 0.6,
                secondaryOpacity: 0.42,
                primaryRadius: 24,
                secondaryRadius: 18,
                primaryOffset: CGSize(width: 6 + jitter, height: 8 + jitter),
                secondaryOffset: CGSize(width: -5 - jitter, height: -6 - jitter),
                shadowLineWidth: 32,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.6
            )
        }
    }

    private func quickPulse(elapsed: TimeInterval, period: Double) -> Double {
        let phase = (elapsed / period) * Double.pi * 2
        return (sin(phase) + 1) * 0.5
    }

    private func slowPulse(elapsed: TimeInterval, period: Double) -> Double {
        let phase = (elapsed / period) * Double.pi * 2
        return (sin(phase) + 1) * 0.5
    }

    private func doneSettle(elapsed: TimeInterval) -> (intensity: Double, tighten: Double) {
        if elapsed <= 0.25 {
            let t = elapsed / 0.25
            return (intensity: 0.05 * easeOut(t), tighten: 2.0 * easeOut(t))
        }
        if elapsed <= 1.1 {
            let t = (elapsed - 0.25) / 0.85
            return (intensity: 0.05 * (1 - easeOut(t)), tighten: 2.0 * (1 - easeOut(t)))
        }
        return (intensity: 0, tighten: 0)
    }

    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

#Preview {
    BackgroundAtmosphere(status: .listening, audioLevel: 0.7)
}

private struct AtmospherePlate: View {
    let config: AtmosphereConfig

    var body: some View {
        GeometryReader { proxy in
            let corner: CGFloat = 36
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            let fill = LinearGradient(
                colors: config.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
                shape
                    .fill(fill)

                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(proxy.size.width, proxy.size.height) * 0.55
                        )
                    )
                    .blendMode(.screen)

                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 20,
                            endRadius: 320
                        )
                    )
                    .blendMode(.screen)

                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.clear
                            ],
                            center: .bottomTrailing,
                            startRadius: 30,
                            endRadius: max(proxy.size.width, proxy.size.height) * 0.6
                        )
                    )
                    .blendMode(.screen)

                InnerEdgeHighlight(
                    shape: shape,
                    highlightColor: Color.white.opacity(0.18),
                    shadowColor: Color.black.opacity(0.35),
                    radius: 6,
                    lineWidth: 10
                )

                InnerShadow(
                    shape: shape,
                    color: config.primaryShadow.opacity(config.primaryOpacity),
                    radius: config.primaryRadius,
                    offset: config.primaryOffset,
                    lineWidth: config.shadowLineWidth
                )
                .blendMode(.multiply)

                InnerShadow(
                    shape: shape,
                    color: config.secondaryShadow.opacity(config.secondaryOpacity),
                    radius: config.secondaryRadius,
                    offset: config.secondaryOffset,
                    lineWidth: config.shadowLineWidth * 0.7
                )
                .blendMode(.multiply)

                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                config.vignetteColor.opacity(config.vignetteOpacity),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 120,
                            endRadius: max(proxy.size.width, proxy.size.height)
                        )
                    )
                    .blendMode(.multiply)
            }
            .compositingGroup()
            .padding(8)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct InnerEdgeHighlight: View {
    let shape: RoundedRectangle
    let highlightColor: Color
    let shadowColor: Color
    let radius: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            shape
                .stroke(highlightColor, lineWidth: lineWidth)
                .blur(radius: radius)
                .offset(x: -3, y: -3)
                .mask(shape.fill(Color.black))
                .blendMode(.screen)

            shape
                .stroke(shadowColor, lineWidth: lineWidth)
                .blur(radius: radius)
                .offset(x: 3, y: 3)
                .mask(shape.fill(Color.black))
                .blendMode(.multiply)
        }
    }
}

private struct InnerShadow: View {
    let shape: RoundedRectangle
    let color: Color
    let radius: CGFloat
    let offset: CGSize
    let lineWidth: CGFloat

    var body: some View {
        shape
            .stroke(color, lineWidth: lineWidth)
            .blur(radius: radius)
            .offset(x: offset.width, y: offset.height)
            .mask(shape.fill(Color.black))
    }
}

private struct AtmosphereConfig {
    let gradient: [Color]
    let primaryShadow: Color
    let secondaryShadow: Color
    let primaryOpacity: Double
    let secondaryOpacity: Double
    let primaryRadius: CGFloat
    let secondaryRadius: CGFloat
    let primaryOffset: CGSize
    let secondaryOffset: CGSize
    let shadowLineWidth: CGFloat
    let vignetteColor: Color
    let vignetteOpacity: Double
}
