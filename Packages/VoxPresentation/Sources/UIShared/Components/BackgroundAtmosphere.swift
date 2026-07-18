import SwiftUI

public struct BackgroundAtmosphere: View {
    let status: RecorderStatus
    let audioLevel: Double?
    @State private var stateStart = Date()
    // 音频电平的弹簧积分状态（位置 + 速度），由渲染帧驱动 → velocity-aware 且 display-synced
    @State private var springLevel: Double = 0
    @State private var springVelocity: Double = 0
    @State private var lastFrame: Date?
    @State private var previousStatus: RecorderStatus?
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 阶段交叉淡出时长：色彩缓缓 morph 而非硬切，是「丝滑流转」的核心。
    /// 调长以求更从容柔和（less is more）。
    private static let crossfadeDuration: TimeInterval = 0.9

    public init(status: RecorderStatus = .idle, audioLevel: Double? = nil) {
        self.status = status
        self.audioLevel = audioLevel
    }

    public var body: some View {
        // 「减弱动态效果」开启时暂停时间轴动画，冻结持续脉动/抖动 + 转场，仅保留静态渐变
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            // reduceMotion 时冻结 elapsed，使 slowPulse / error 抖动 / doneSettle / 转场全部保持静态
            let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(stateStart)
            // reduceMotion 时忽略音频电平驱动的脉动
            let effectiveAudioLevel = reduceMotion ? 0 : springLevel
            let config = atmosphereConfig(
                for: status,
                elapsed: elapsed,
                audioLevel: effectiveAudioLevel,
                theme: theme
            )
            // 阶段切换的「呼吸」：入场膨胀/完成内收 + 同色光晕，纯靠色彩语言传达流转
            let dynamics = transitionDynamics(status: status, transitionElapsed: elapsed)

            ZStack {
                // 上一阶段画面在过渡窗口内交叉淡出，色彩流转而非硬切
                if !reduceMotion,
                   let previous = previousStatus,
                   let progress = crossfadeProgress(elapsed: elapsed),
                   progress < 1 {
                    let previousConfig = atmosphereConfig(
                        for: previous,
                        elapsed: 0,
                        audioLevel: 0,
                        theme: theme
                    )
                    AtmospherePlate(config: previousConfig, audioLevel: 0, elapsed: 0)
                        .opacity(1 - progress)
                }

                AtmospherePlate(config: config, audioLevel: effectiveAudioLevel, elapsed: elapsed)
                    .opacity(incomingOpacity(elapsed: elapsed))
                    .scaleEffect(dynamics.scale)

                // 转场「呼吸」光晕：入场时中心泛起一层与阶段同色的柔光，随即消散
                if dynamics.bloom > 0.001 {
                    TransitionBloom(color: config.primaryShadow, opacity: dynamics.bloom)
                }
            }
            .ignoresSafeArea()
            .onChange(of: context.date) { _, now in
                // 每渲染帧推进音频弹簧：从当前值以真实 dt 追踪目标电平，继承速度
                stepAudioSpring(now: now)
            }
        }
        .onChange(of: status) { oldValue, _ in
            // 记录上一阶段用于交叉淡出；重置 stateStart 使转场/脉动从 0 起算（Date 非 animatable，
            // 直接赋值，不再包 no-op 的 withAnimation）
            previousStatus = oldValue
            stateStart = Date()
            if status != .listening {
                // 离开录音：目标归零，弹簧自然衰减回落
                springLevel = 0
                springVelocity = 0
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

    // MARK: - 转场节奏

    /// 交叉淡出进度（0→1，smoothstep）。首次出现（无上一阶段）返回 nil，不做淡出。
    private func crossfadeProgress(elapsed: TimeInterval) -> Double? {
        guard previousStatus != nil else { return nil }
        return AtmosphereTransition.crossfade(elapsed: elapsed, duration: Self.crossfadeDuration)
    }

    /// 入场画面的不透明度：随交叉淡出淡入；首次出现或 reduceMotion 时直接满值。
    private func incomingOpacity(elapsed: TimeInterval) -> Double {
        guard !reduceMotion, previousStatus != nil else { return 1 }
        return AtmosphereTransition.crossfade(elapsed: elapsed, duration: Self.crossfadeDuration)
    }

    /// 阶段入场的「呼吸」动力学：整层缩放 + 中心光晕强度。reduceMotion 时静止。
    private func transitionDynamics(
        status: RecorderStatus,
        transitionElapsed te: TimeInterval
    ) -> (scale: CGFloat, bloom: Double) {
        guard !reduceMotion else { return (1, 0) }
        return AtmosphereTransition.dynamics(status: status, transitionElapsed: te)
    }

    private func atmosphereConfig(
        for status: RecorderStatus,
        elapsed: TimeInterval,
        audioLevel: Double?,
        theme: Theme
    ) -> AtmosphereConfig {
        let basePulse = slowPulse(elapsed: elapsed, period: 10)
        switch status {
        case .idle:
            return AtmosphereConfig(
                primaryShadow: Color(red: 0.55, green: 0.6, blue: 0.8),
                primaryOpacity: 0.3 + basePulse * 0.08,
                primaryRadius: 26 + basePulse * 4,
                primaryOffset: CGSize(width: 6, height: 8),
                shadowLineWidth: 30,
                edgeShadowColor: Color(red: 0.6, green: 0.65, blue: 0.85),
                edgeShadowOpacity: 0.35,
                edgeShadowInset: 40,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.32,
                baseGradientColors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.88, green: 0.92, blue: 1.0),
                    Color(red: 0.82, green: 0.86, blue: 0.96),
                    Color(red: 0.76, green: 0.8, blue: 0.92),
                    Color(red: 0.7, green: 0.74, blue: 0.88)
                ],
                directionalGradients: AtmosphereGradientPresets.directions(for: .idle, modulation: basePulse),
                highlightShadowOpacity: 0.6,
                darkShadowOpacity: 0.08
            )
        case .listening:
            let level = clamp(audioLevel ?? 0, min: 0, max: 1)
            let energy = 0.08 + pow(level, 0.85) * 0.92
            return AtmosphereConfig(
                primaryShadow: Color(red: 0.3, green: 0.7, blue: 0.75),
                primaryOpacity: 0.35 + energy * 0.35,
                primaryRadius: 24 + energy * 14,
                primaryOffset: CGSize(width: 6 + energy * 6, height: 8 + energy * 7),
                shadowLineWidth: 32,
                edgeShadowColor: Color(red: 0.3, green: 0.68, blue: 0.72),
                edgeShadowOpacity: 0.35 + energy * 0.35,
                edgeShadowInset: 40 + energy * 50,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.4 + energy * 0.22,
                baseGradientColors: [
                    Color(red: 0.85, green: 0.98, blue: 0.96),
                    Color(red: 0.7, green: 0.92, blue: 0.9),
                    Color(red: 0.55, green: 0.84, blue: 0.84),
                    Color(red: 0.4, green: 0.74, blue: 0.78),
                    Color(red: 0.28, green: 0.62, blue: 0.7)
                ],
                directionalGradients: AtmosphereGradientPresets.directions(for: .listening, modulation: energy),
                highlightShadowOpacity: 0.5 + energy * 0.3,
                darkShadowOpacity: 0.06 + energy * 0.08
            )
        case .transcribing:
            let breathe = slowPulse(elapsed: elapsed, period: 6.5)
            return AtmosphereConfig(
                primaryShadow: Color(red: 0.45, green: 0.55, blue: 0.85),
                primaryOpacity: 0.35 + breathe * 0.15,
                primaryRadius: 24 + breathe * 8,
                primaryOffset: CGSize(width: 6, height: 8),
                shadowLineWidth: 30,
                edgeShadowColor: Color(red: 0.45, green: 0.55, blue: 0.82),
                edgeShadowOpacity: 0.35 + breathe * 0.1,
                edgeShadowInset: 40 + breathe * 15,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.45 + breathe * 0.08,
                baseGradientColors: [
                    Color(red: 0.9, green: 0.92, blue: 1.0),
                    Color(red: 0.78, green: 0.82, blue: 0.98),
                    Color(red: 0.64, green: 0.72, blue: 0.94),
                    Color(red: 0.5, green: 0.6, blue: 0.88),
                    Color(red: 0.38, green: 0.48, blue: 0.8)
                ],
                directionalGradients: AtmosphereGradientPresets.directions(for: .transcribing, modulation: breathe),
                highlightShadowOpacity: 0.55,
                darkShadowOpacity: 0.08
            )
        case .refining:
            let pulse = slowPulse(elapsed: elapsed, period: 7.5)
            return AtmosphereConfig(
                primaryShadow: Color(red: 0.65, green: 0.5, blue: 0.85),
                primaryOpacity: 0.35 + pulse * 0.15,
                primaryRadius: 26 + pulse * 6,
                primaryOffset: CGSize(width: 6, height: 8),
                shadowLineWidth: 32,
                edgeShadowColor: Color(red: 0.62, green: 0.48, blue: 0.82),
                edgeShadowOpacity: 0.35 + pulse * 0.1,
                edgeShadowInset: 40 + pulse * 15,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.5,
                baseGradientColors: [
                    Color(red: 0.94, green: 0.9, blue: 1.0),
                    Color(red: 0.86, green: 0.78, blue: 0.98),
                    Color(red: 0.74, green: 0.64, blue: 0.92),
                    Color(red: 0.62, green: 0.5, blue: 0.84),
                    Color(red: 0.5, green: 0.38, blue: 0.76)
                ],
                directionalGradients: AtmosphereGradientPresets.directions(for: .refining, modulation: pulse),
                highlightShadowOpacity: 0.5,
                darkShadowOpacity: 0.1
            )
        case .done:
            let settle = doneSettle(elapsed: elapsed)
            return AtmosphereConfig(
                primaryShadow: Color(red: 0.4, green: 0.75, blue: 0.6),
                primaryOpacity: 0.3 + settle.intensity,
                primaryRadius: 24 - settle.tighten,
                primaryOffset: CGSize(width: 6, height: 8),
                shadowLineWidth: 30,
                edgeShadowColor: Color(red: 0.38, green: 0.72, blue: 0.58),
                edgeShadowOpacity: 0.35,
                edgeShadowInset: 40,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.38,
                baseGradientColors: [
                    Color(red: 0.88, green: 0.98, blue: 0.92),
                    Color(red: 0.74, green: 0.94, blue: 0.84),
                    Color(red: 0.58, green: 0.86, blue: 0.74),
                    Color(red: 0.44, green: 0.78, blue: 0.66),
                    Color(red: 0.34, green: 0.68, blue: 0.56)
                ],
                directionalGradients: AtmosphereGradientPresets.directions(for: .done, modulation: settle.intensity * 20),
                highlightShadowOpacity: 0.6,
                darkShadowOpacity: 0.07
            )
        case .error:
            // reduceMotion 时不做左右抖动，保持静态偏移
            let jitter = reduceMotion ? 0 : Double(sin(elapsed * 6)) * 2
            return AtmosphereConfig(
                primaryShadow: Color(red: 0.8, green: 0.4, blue: 0.45),
                primaryOpacity: 0.4,
                primaryRadius: 24,
                primaryOffset: CGSize(width: 6 + jitter, height: 8 + jitter),
                shadowLineWidth: 32,
                edgeShadowColor: Color(red: 0.78, green: 0.38, blue: 0.42),
                edgeShadowOpacity: 0.4,
                edgeShadowInset: 50,
                vignetteColor: theme.palette.backgroundVignette,
                vignetteOpacity: 0.6,
                baseGradientColors: [
                    Color(red: 1.0, green: 0.92, blue: 0.9),
                    Color(red: 0.98, green: 0.8, blue: 0.78),
                    Color(red: 0.92, green: 0.66, blue: 0.64),
                    Color(red: 0.84, green: 0.5, blue: 0.5),
                    Color(red: 0.74, green: 0.38, blue: 0.4)
                ],
                directionalGradients: AtmosphereGradientPresets.directions(for: .error, modulation: abs(jitter) / 2),
                highlightShadowOpacity: 0.4,
                darkShadowOpacity: 0.12
            )
        }
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

// MARK: - TransitionBloom

/// 阶段入场/完成时中心泛起的一层同色柔光。纯 opacity + 径向渐变，不触发布局，
/// 由调用方按呼吸曲线传入 opacity，随即消散——即「呼吸」的可见部分。
private struct TransitionBloom: View {
    let color: Color
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let maxDim = max(proxy.size.width, proxy.size.height)
            RadialGradient(
                colors: [
                    color.opacity(0.32),
                    color.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: maxDim * 0.62
            )
            .blendMode(.screen)
            .opacity(opacity)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - AtmospherePlate

private struct AtmospherePlate: View {
    let config: AtmosphereConfig
    let audioLevel: Double
    let elapsed: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let shape = Rectangle()
            let maxDim = max(proxy.size.width, proxy.size.height)
            let inset = config.edgeShadowInset

            ZStack {
                // 多色径向渐变底层
                RadialGradient(
                    gradient: Gradient(colors: config.baseGradientColors),
                    center: .center,
                    startRadius: maxDim * 0.02,
                    endRadius: maxDim * 0.7
                )

                ForEach(Array(config.directionalGradients.enumerated()), id: \.offset) { _, gradient in
                    LinearGradient(
                        colors: gradient.colors,
                        startPoint: gradient.start.unitPoint,
                        endPoint: gradient.end.unitPoint
                    )
                    .opacity(gradient.opacity)
                    .blendMode(.screen)
                }

                // 毛玻璃材质层
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.18)

                // 四周边缘彩色渐变光晕
                EdgeShadow(
                    color: config.edgeShadowColor,
                    opacity: config.edgeShadowOpacity,
                    inset: inset,
                    size: proxy.size
                )

                // 主内阴影（彩色）
                InnerShadow(
                    color: config.primaryShadow.opacity(config.primaryOpacity),
                    radius: config.primaryRadius,
                    offset: config.primaryOffset,
                    lineWidth: config.shadowLineWidth
                )

                // 边缘柔和渐变
                shape
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.clear,
                                config.vignetteColor.opacity(config.vignetteOpacity * 0.5)
                            ],
                            center: .center,
                            startRadius: maxDim * 0.35,
                            endRadius: maxDim * 0.8
                        )
                    )
            }
            // 拟态高光阴影（左上亮）
            .shadow(color: Color.white.opacity(config.highlightShadowOpacity * 0.4), radius: 12, x: -6, y: -6)
            // 拟态彩色阴影（右下，使用主题色代替黑色）
            .shadow(color: config.primaryShadow.opacity(config.darkShadowOpacity * 1.5), radius: 12, x: 6, y: 6)
            .compositingGroup()
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

// MARK: - EdgeShadow

private struct EdgeShadow: View {
    let color: Color
    let opacity: Double
    let inset: CGFloat
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            let edges: [UnitPoint] = [.top, .bottom, .leading, .trailing]
            for edge in edges {
                let startPoint: CGPoint
                let endPoint: CGPoint

                switch edge {
                case .top:
                    startPoint = CGPoint(x: canvasSize.width / 2, y: 0)
                    endPoint = CGPoint(x: canvasSize.width / 2, y: inset)
                case .bottom:
                    startPoint = CGPoint(x: canvasSize.width / 2, y: canvasSize.height)
                    endPoint = CGPoint(x: canvasSize.width / 2, y: canvasSize.height - inset)
                case .leading:
                    startPoint = CGPoint(x: 0, y: canvasSize.height / 2)
                    endPoint = CGPoint(x: inset, y: canvasSize.height / 2)
                case .trailing:
                    startPoint = CGPoint(x: canvasSize.width, y: canvasSize.height / 2)
                    endPoint = CGPoint(x: canvasSize.width - inset, y: canvasSize.height / 2)
                default:
                    continue
                }

                let gradient = Gradient(colors: [
                    color.opacity(opacity),
                    color.opacity(opacity * 0.4),
                    Color.clear
                ])

                context.fill(
                    Path(CGRect(origin: .zero, size: canvasSize)),
                    with: .linearGradient(
                        gradient,
                        startPoint: startPoint,
                        endPoint: endPoint
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - InnerShadow

private struct InnerShadow: View {
    let color: Color
    let radius: CGFloat
    let offset: CGSize
    let lineWidth: CGFloat

    var body: some View {
        let shape = Rectangle()
        shape
            .stroke(color, lineWidth: lineWidth)
            .blur(radius: radius)
            .offset(x: offset.width, y: offset.height)
            .mask(shape.fill(Color.black))
    }
}

// MARK: - AtmosphereConfig

enum AtmosphereGradientAnchor: String, Hashable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    var unitPoint: UnitPoint {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }
}

struct AtmosphereDirectionalGradient {
    let start: AtmosphereGradientAnchor
    let end: AtmosphereGradientAnchor
    let colors: [Color]
    let opacity: Double
}

enum AtmosphereGradientPresets {
    /// 每个阶段仅一层方向光晕（less is more：原本 2–3 层 .screen 叠加是「高级感过载」，
    /// 砍到单层即足以表达空间倾向，画面更干净、更柔和）。保留各阶段最具代表性的方向与色。
    static func directions(for status: RecorderStatus, modulation: Double) -> [AtmosphereDirectionalGradient] {
        let amount = clamp(modulation, min: 0, max: 1)
        switch status {
        case .idle:
            return [
                AtmosphereDirectionalGradient(
                    start: .bottomLeading,
                    end: .topTrailing,
                    colors: [
                        Color(red: 0.82, green: 0.95, blue: 1.0),
                        Color.clear
                    ],
                    opacity: 0.2 + amount * 0.06
                )
            ]
        case .listening:
            return [
                AtmosphereDirectionalGradient(
                    start: .leading,
                    end: .trailing,
                    colors: [
                        Color(red: 0.62, green: 0.98, blue: 0.88),
                        Color.clear
                    ],
                    opacity: 0.18 + amount * 0.2
                )
            ]
        case .transcribing:
            return [
                AtmosphereDirectionalGradient(
                    start: .topLeading,
                    end: .bottomTrailing,
                    colors: [
                        Color(red: 0.86, green: 0.88, blue: 1.0),
                        Color.clear
                    ],
                    opacity: 0.2 + amount * 0.14
                )
            ]
        case .refining:
            return [
                AtmosphereDirectionalGradient(
                    start: .top,
                    end: .bottom,
                    colors: [
                        Color(red: 0.8, green: 0.64, blue: 1.0),
                        Color.clear
                    ],
                    opacity: 0.18 + amount * 0.12
                )
            ]
        case .done:
            return [
                AtmosphereDirectionalGradient(
                    start: .bottomLeading,
                    end: .topTrailing,
                    colors: [
                        Color(red: 0.74, green: 1.0, blue: 0.84),
                        Color.clear
                    ],
                    opacity: 0.18 + amount * 0.14
                )
            ]
        case .error:
            return [
                AtmosphereDirectionalGradient(
                    start: .leading,
                    end: .trailing,
                    colors: [
                        Color(red: 1.0, green: 0.76, blue: 0.62),
                        Color.clear
                    ],
                    opacity: 0.2 + amount * 0.12
                )
            ]
        }
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

private struct AtmosphereConfig {
    let primaryShadow: Color
    let primaryOpacity: Double
    let primaryRadius: CGFloat
    let primaryOffset: CGSize
    let shadowLineWidth: CGFloat
    let edgeShadowColor: Color
    let edgeShadowOpacity: Double
    let edgeShadowInset: CGFloat
    let vignetteColor: Color
    let vignetteOpacity: Double
    // 径向渐变色（4-5种颜色）
    let baseGradientColors: [Color]
    // 不同方向的线性渐变叠加，增强空间感
    let directionalGradients: [AtmosphereDirectionalGradient]
    // 拟态阴影
    let highlightShadowOpacity: Double
    let darkShadowOpacity: Double
}

// MARK: - 2. Neumorphism + RadialGradient
struct NeumorphicRadialCard: View {
    var body: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.85, green: 0.9, blue: 1.0),
                    Color(red: 0.8, green: 0.85, blue: 0.95),
                    Color(red: 0.75, green: 0.8, blue: 0.9)
                ]),
                center: .center,
                startRadius: 10,
                endRadius: 250
            )
            .frame(width: 250, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .shadow(color: Color.white.opacity(0.8), radius: 10, x: -6, y: -6)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 6, y: 6)
        }
    }
}

struct NeumorphicRadialCard_Previews: PreviewProvider {
    static var previews: some View {
        NeumorphicRadialCard()
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
