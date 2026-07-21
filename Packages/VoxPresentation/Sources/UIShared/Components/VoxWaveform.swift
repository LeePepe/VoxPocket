import SwiftUI

/// 五柱语音波形。
///
/// - `.live(level:)`：由音频电平驱动（listening），内部做一阶低通平滑，避免抖动。
/// - `.shimmer`：不定态流光（transcribing / refining，无音频），一道行波扫过五柱。
/// - `.rest`：静止在中位高度。
///
/// 全程尊重 `accessibilityReduceMotion`：关闭动画，静止在中位高度。
@MainActor
public struct VoxWaveform: View {
    public enum Mode: Equatable {
        case live(level: Double)
        case shimmer
        case rest
    }

    private let mode: Mode
    private let tint: Color

    @State private var start = Date()
    @State private var smoothedLevel: Double = 0
    @State private var lastFrame: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barCount = 5
    private static let barWidth: CGFloat = 4
    private static let spacing: CGFloat = 3
    private static let minRatio: CGFloat = 0.24
    private static let restRatio: CGFloat = 0.5

    public init(mode: Mode, tint: Color) {
        self.mode = mode
        self.tint = tint
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSince(start)
            GeometryReader { proxy in
                HStack(spacing: Self.spacing) {
                    ForEach(0 ..< Self.barCount, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(tint)
                            .frame(width: Self.barWidth,
                                   height: barHeight(index: index, t: t, maxHeight: proxy.size.height))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .onChange(of: context.date) { _, now in
                stepSmoothing(now: now)
            }
        }
    }

    /// 用渲染帧真实时间步进对音频电平做一阶低通，避免逐帧跳变。
    private func stepSmoothing(now: Date) {
        guard case let .live(level) = mode, !reduceMotion else {
            lastFrame = now
            return
        }
        let dt = lastFrame.map { now.timeIntervalSince($0) } ?? 0
        lastFrame = now
        let target = max(0, min(1, level))
        // 时间常数 ~0.12s：约 8Hz 跟随，柔而不糊。
        let alpha = min(1, dt / 0.12)
        smoothedLevel += (target - smoothedLevel) * alpha
    }

    private func barHeight(index: Int, t: TimeInterval, maxHeight: CGFloat) -> CGFloat {
        guard !reduceMotion else { return maxHeight * Self.restRatio }
        let minHeight = maxHeight * Self.minRatio
        let span = maxHeight - minHeight

        switch mode {
        case .rest:
            return maxHeight * Self.restRatio
        case .shimmer:
            // 一道行波（0…1），相邻柱相位差营造扫过感。
            let wave = (sin(t * 3.4 - Double(index) * 0.9) + 1) / 2
            return minHeight + span * CGFloat(0.32 + 0.68 * wave)
        case .live:
            // 中间柱权重高、两侧低，形成对称波形；叠加轻微相位摆动。
            let center = 1 - abs(Double(index) - 2) / 2.6
            let wobble = (sin(t * 6 + Double(index) * 1.25) + 1) / 2
            let amplitude = smoothedLevel * (0.55 + 0.45 * center)
            let dynamic = amplitude * (0.6 + 0.4 * wobble)
            return minHeight + span * CGFloat(max(0.1, min(1, dynamic)))
        }
    }
}

#Preview("live") {
    VoxWaveform(mode: .live(level: 0.7), tint: .blue)
        .frame(width: 44, height: 26)
        .padding()
}

#Preview("shimmer") {
    VoxWaveform(mode: .shimmer, tint: .purple)
        .frame(width: 44, height: 26)
        .padding()
}
