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
                    AnimatableAtmosphereGlassPlate(
                        rgbVector: AtmosphereRGBVector(status: status),
                        breath: breath,
                        opacity: AtmosphereGlass.washOpacity(for: colorScheme, energy: breath)
                    )
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

// MARK: - Continuous Animatable 5-Blob RGB GlassPlate (Zero Node Replacement / Zero Flash)

/// Continuous 15-component sRGB vector (`5 blobs × (r, g, b)`) conforming to `VectorArithmetic`
/// so SwiftUI interpolates all 5 `RadialGradient` colors smoothly frame-by-frame without view replacement.
struct AtmosphereRGBVector: VectorArithmetic, Equatable, Sendable {
    var c0r: Double = 0, c0g: Double = 0, c0b: Double = 0
    var c1r: Double = 0, c1g: Double = 0, c1b: Double = 0
    var c2r: Double = 0, c2g: Double = 0, c2b: Double = 0
    var c3r: Double = 0, c3g: Double = 0, c3b: Double = 0
    var c4r: Double = 0, c4g: Double = 0, c4b: Double = 0

    init() {}

    init(status: RecorderStatus) {
        let comps = AtmosphereGlass.colorComponents(for: status)
        guard comps.count >= 5 else { return }
        c0r = comps[0].r; c0g = comps[0].g; c0b = comps[0].b
        c1r = comps[1].r; c1g = comps[1].g; c1b = comps[1].b
        c2r = comps[2].r; c2g = comps[2].g; c2b = comps[2].b
        c3r = comps[3].r; c3g = comps[3].g; c3b = comps[3].b
        c4r = comps[4].r; c4g = comps[4].g; c4b = comps[4].b
    }

    var colors: [Color] {
        [
            Color(.sRGB, red: c0r, green: c0g, blue: c0b, opacity: 1),
            Color(.sRGB, red: c1r, green: c1g, blue: c1b, opacity: 1),
            Color(.sRGB, red: c2r, green: c2g, blue: c2b, opacity: 1),
            Color(.sRGB, red: c3r, green: c3g, blue: c3b, opacity: 1),
            Color(.sRGB, red: c4r, green: c4g, blue: c4b, opacity: 1)
        ]
    }

    static var zero: AtmosphereRGBVector { AtmosphereRGBVector() }

    static func + (lhs: AtmosphereRGBVector, rhs: AtmosphereRGBVector) -> AtmosphereRGBVector {
        var r = AtmosphereRGBVector()
        r.c0r = lhs.c0r + rhs.c0r; r.c0g = lhs.c0g + rhs.c0g; r.c0b = lhs.c0b + rhs.c0b
        r.c1r = lhs.c1r + rhs.c1r; r.c1g = lhs.c1g + rhs.c1g; r.c1b = lhs.c1b + rhs.c1b
        r.c2r = lhs.c2r + rhs.c2r; r.c2g = lhs.c2g + rhs.c2g; r.c2b = lhs.c2b + rhs.c2b
        r.c3r = lhs.c3r + rhs.c3r; r.c3g = lhs.c3g + rhs.c3g; r.c3b = lhs.c3b + rhs.c3b
        r.c4r = lhs.c4r + rhs.c4r; r.c4g = lhs.c4g + rhs.c4g; r.c4b = lhs.c4b + rhs.c4b
        return r
    }

    static func - (lhs: AtmosphereRGBVector, rhs: AtmosphereRGBVector) -> AtmosphereRGBVector {
        var r = AtmosphereRGBVector()
        r.c0r = lhs.c0r - rhs.c0r; r.c0g = lhs.c0g - rhs.c0g; r.c0b = lhs.c0b - rhs.c0b
        r.c1r = lhs.c1r - rhs.c1r; r.c1g = lhs.c1g - rhs.c1g; r.c1b = lhs.c1b - rhs.c1b
        r.c2r = lhs.c2r - rhs.c2r; r.c2g = lhs.c2g - rhs.c2g; r.c2b = lhs.c2b - rhs.c2b
        r.c3r = lhs.c3r - rhs.c3r; r.c3g = lhs.c3g - rhs.c3g; r.c3b = lhs.c3b - rhs.c3b
        r.c4r = lhs.c4r - rhs.c4r; r.c4g = lhs.c4g - rhs.c4g; r.c4b = lhs.c4b - rhs.c4b
        return r
    }

    mutating func scale(by rhs: Double) {
        c0r *= rhs; c0g *= rhs; c0b *= rhs
        c1r *= rhs; c1g *= rhs; c1b *= rhs
        c2r *= rhs; c2g *= rhs; c2b *= rhs
        c3r *= rhs; c3g *= rhs; c3b *= rhs
        c4r *= rhs; c4g *= rhs; c4b *= rhs
    }

    var magnitudeSquared: Double {
        c0r * c0r + c0g * c0g + c0b * c0b +
        c1r * c1r + c1g * c1g + c1b * c1b +
        c2r * c2r + c2g * c2g + c2b * c2b +
        c3r * c3r + c3g * c3g + c3b * c3b +
        c4r * c4r + c4g * c4g + c4b * c4b
    }
}

/// 一组平滑渐变光团，永久常驻不销毁，通过 `Animatable` 连续插值 5 个光团的 sRGB 颜色分量。
private struct AnimatableAtmosphereGlassPlate: View, Animatable {
    var rgbVector: AtmosphereRGBVector
    var breath: Double
    var opacity: Double

    nonisolated var animatableData: AnimatablePair<AtmosphereRGBVector, AnimatablePair<Double, Double>> {
        get { AnimatablePair(rgbVector, AnimatablePair(breath, opacity)) }
        set {
            rgbVector = newValue.first
            breath = newValue.second.first
            opacity = newValue.second.second
        }
    }

    var body: some View {
        let positions = AtmosphereGlass.normalizedPositions()
        let currentColors = rgbVector.colors

        GeometryReader { proxy in
            // 统一坐标画布映射到窗口，窄胶囊也保留与主窗口相同的光团分布。
            let canvas: CGFloat = 400
            // 呼吸：把光团整体放大一点点 + 略提不透明度，克制（scale ≤ 4%）
            let breathScale = 1 + CGFloat(breath) * 0.035

            ZStack {
                ForEach(0..<min(positions.count, currentColors.count), id: \.self) { idx in
                    let pos = positions[idx]
                    let color = currentColors[idx]
                    RadialGradient(
                        stops: [
                            .init(color: color, location: 0),
                            .init(color: color.opacity(0.55), location: 0.45),
                            .init(color: .clear, location: 1)
                        ],
                        center: UnitPoint(x: pos.x, y: pos.y),
                        startRadius: 0,
                        endRadius: canvas * pos.s * breathScale * 0.8
                    )
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
