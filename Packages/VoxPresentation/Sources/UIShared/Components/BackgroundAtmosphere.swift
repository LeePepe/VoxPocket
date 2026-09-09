import SwiftUI

/// 玻璃质感氛围背景。
///
/// 自适应明暗底材与柔和渐变光团，主窗口和浮窗复用同一画法。
/// 阶段由色心区分（见 `AtmosphereGlass`），阶段间色彩交叉淡出而非硬切。
/// listening 时光团随真实音频电平（弹簧驱动，velocity-aware）轻呼吸。
/// 全程尊重 `accessibilityReduceMotion`：关闭时间轴、呼吸与转场，仅留静态渐变。
public struct BackgroundAtmosphere: View {
    let status: RecorderStatus
    let audioLevel: Double?
    private let tracksAudioContinuously: Bool
    // 音频电平的弹簧积分状态（位置 + 速度），由渲染帧驱动 → velocity-aware 且 display-synced
    @State private var springLevel: Double = 0
    @State private var springVelocity: Double = 0
    @State private var lastFrame: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    public init(status: RecorderStatus = .idle, audioLevel: Double? = nil, tracksAudioContinuously: Bool = true) {
        self.status = status
        self.audioLevel = audioLevel
        self.tracksAudioContinuously = tracksAudioContinuously
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: reduceMotion || !tracksAudioContinuously || status != .listening)) { context in
            // listening 时音频弹簧驱动的轻微呼吸强度（0…~1.2）；reduceMotion / 非录音时为 0
            let level = tracksAudioContinuously ? springLevel : (audioLevel ?? 0)
            let breath = (reduceMotion || status != .listening || !level.isFinite) ? 0 : clamp(level, min: 0, max: 1)

            ZStack {
                AtmosphereGlass.baseColor(for: colorScheme)

                if AtmosphereGlass.allowsAtmosphere(reduceTransparency: reduceTransparency,
                                                   increasedContrast: contrast == .increased) {
                    // 材质位于染色层之下，避免在浮窗蒙版内遮住阶段色。
                    Rectangle().fill(.ultraThinMaterial)
                    GlassPlate(blobs: AtmosphereGlass.blobs(for: status), breath: breath,
                               opacity: AtmosphereGlass.washOpacity(for: colorScheme, energy: breath))
                        .id(status)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: AtmosphereGlass.transitionDuration), value: status)
            .ignoresSafeArea()
            .onChange(of: context.date) { _, now in
                if tracksAudioContinuously { stepAudioSpring(now: now) }
            }
        }
        .onChange(of: status) { _, _ in
            if status != .listening {
                springLevel = 0
                springVelocity = 0
                lastFrame = nil
            }
        }
    }

    /// 用渲染帧的真实时间步进音频弹簧。reduceMotion 时不追踪，保持静止。
    private func stepAudioSpring(now: Date) {
        guard !reduceMotion else {
            lastFrame = now
            return
        }
        let dt = lastFrame.map { now.timeIntervalSince($0) } ?? 0
        lastFrame = now
        let target = clamp(audioLevel ?? 0, min: 0, max: 1)
        let stepped = AtmosphereTransition.springStep(
            position: springLevel,
            velocity: springVelocity,
            target: target,
            dt: dt
        )
        springLevel = clamp(stepped.position, min: 0, max: 1.2)
        springVelocity = stepped.velocity
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

// MARK: - GlassPlate

/// 一组平滑渐变光团，不依赖会在复杂窗口蒙版中丢失的离屏模糊层。
/// `breath`（0…~1.2）在 listening 时轻微放大/提亮光团，制造随声呼吸感（不驱动布局）。
private struct GlassPlate: View {
    let blobs: [AtmosphereBlob]
    let breath: Double
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            // 统一坐标画布映射到窗口，窄胶囊也保留与主窗口相同的光团分布。
            let canvas: CGFloat = 400
            // 呼吸：把光团整体放大一点点 + 略提不透明度，克制（scale ≤ 4%）
            let breathScale = 1 + CGFloat(breath) * 0.035

            ZStack {
                ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                    RadialGradient(stops: [.init(color: blob.color, location: 0),
                                           .init(color: blob.color.opacity(0.55), location: 0.45),
                                           .init(color: .clear, location: 1)],
                                   center: UnitPoint(x: blob.x, y: blob.y), startRadius: 0,
                                   endRadius: canvas * blob.scale * breathScale * 0.8)
                }
            }
            .frame(width: canvas, height: canvas)
            .scaleEffect(x: proxy.size.width / canvas, y: proxy.size.height / canvas, anchor: .topLeading)
            .opacity(opacity)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    BackgroundAtmosphere(status: .listening, audioLevel: 0.7)
}
