#if os(macOS)
import SwiftUI

/// 把主界面的柔调光团收在岛内：上沿轻染、下沿柔光，阅读区仍保持深色。
@MainActor
public struct QuickRecordingPhaseSurface: View {
    private let status: RecorderStatus
    private let audioLevel: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(status: RecorderStatus, audioLevel: Double? = nil) {
        self.status = status
        self.audioLevel = audioLevel
    }

    public var body: some View {
        ZStack {
            QuickRecordingColors.neutrals.card
            if QuickRecordingColors.allowsAtmosphere(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased) {
                PhaseWash(status: status, energy: reduceMotion ? 0 : QuickRecordingColors.energy(status: status, audioLevel: audioLevel))
                    .id(status)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: QuickRecordingColors.transitionDuration), value: status)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private struct PhaseWash: View {
    let status: RecorderStatus
    let energy: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colors: [Color] { QuickRecordingColors.atmosphere(status) }
    private var strength: Double { status == .idle ? 0.35 : 1 }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(colors: [colors[0].opacity(QuickRecordingColors.leadingWashOpacity * strength), .clear],
                               center: .topLeading, startRadius: 0, endRadius: geometry.size.width * 0.62)
                RadialGradient(colors: [colors[2].opacity(QuickRecordingColors.trailingWashOpacity * strength), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.52)
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .opacity((QuickRecordingColors.baseRibbonOpacity + energy * QuickRecordingColors.audioRibbonBoost) * strength)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                  .init(color: .clear, location: 0.45),
                                                  .init(color: .white, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: energy)
    }
}
#endif
