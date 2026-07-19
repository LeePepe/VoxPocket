import SwiftUI

/// 玻璃质感氛围背景。
///
/// 近白底 + 一组模糊彩色光团（宝石柔调、和谐多彩）+ 磨砂材质层，透过磨砂洗出高级感。
/// 阶段由色心区分（见 `AtmosphereGlass`），阶段间色彩交叉淡出而非硬切。
/// listening 时光团随真实音频电平（弹簧驱动，velocity-aware）轻呼吸。
/// 全程尊重 `accessibilityReduceMotion`：关闭时间轴、呼吸与转场，仅留静态渐变。
public struct BackgroundAtmosphere: View {
    let status: RecorderStatus
    let audioLevel: Double?
    @State private var stateStart = Date()
    // 音频电平的弹簧积分状态（位置 + 速度），由渲染帧驱动 → velocity-aware 且 display-synced
    @State private var springLevel: Double = 0
    @State private var springVelocity: Double = 0
    @State private var lastFrame: Date?
    @State private var previousStatus: RecorderStatus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 阶段交叉淡出时长：色彩缓缓 morph 而非硬切。
    private static let crossfadeDuration: TimeInterval = 0.9

    public init(status: RecorderStatus = .idle, audioLevel: Double? = nil) {
        self.status = status
        self.audioLevel = audioLevel
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(stateStart)
            // listening 时音频弹簧驱动的轻微呼吸强度（0…~1.2）；reduceMotion / 非录音时为 0
            let breath = (reduceMotion || status != .listening) ? 0 : springLevel

            ZStack {
                AtmosphereGlass.baseColor

                // 上一阶段光团在过渡窗口内交叉淡出，色彩流转而非硬切
                if !reduceMotion,
                   let previous = previousStatus,
                   let progress = crossfadeProgress(elapsed: elapsed),
                   progress < 1 {
                    GlassPlate(blobs: AtmosphereGlass.blobs(for: previous), breath: 0)
                        .opacity(1 - progress)
                }

                GlassPlate(blobs: AtmosphereGlass.blobs(for: status), breath: breath)
                    .opacity(incomingOpacity(elapsed: elapsed))

                // 磨砂玻璃层：把彩色光团柔化融合、洗出高级质感
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()
            .onChange(of: context.date) { _, now in
                stepAudioSpring(now: now)
            }
        }
        .onChange(of: status) { oldValue, _ in
            // 记录上一阶段用于交叉淡出；重置 stateStart 使转场从 0 起算
            previousStatus = oldValue
            stateStart = Date()
            if status != .listening {
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

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

// MARK: - GlassPlate

/// 一层玻璃画面：近白底之上的一组模糊彩色光团。
/// `breath`（0…~1.2）在 listening 时轻微放大/提亮光团，制造随声呼吸感（不驱动布局）。
private struct GlassPlate: View {
    let blobs: [AtmosphereBlob]
    let breath: Double

    var body: some View {
        GeometryReader { proxy in
            let minDim = min(proxy.size.width, proxy.size.height)
            // 呼吸：把光团整体放大一点点 + 略提不透明度，克制（scale ≤ 4%）
            let breathScale = 1 + CGFloat(breath) * 0.035
            let breathOpacity = 0.72 + breath * 0.14

            ZStack {
                ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                    Circle()
                        .fill(blob.color)
                        .frame(width: minDim * blob.scale * breathScale,
                               height: minDim * blob.scale * breathScale)
                        .position(x: proxy.size.width * blob.x,
                                  y: proxy.size.height * blob.y)
                        .blur(radius: minDim * 0.22)
                }
            }
            .opacity(min(0.9, breathOpacity))
        }
        .ignoresSafeArea()
    }
}

#Preview {
    BackgroundAtmosphere(status: .listening, audioLevel: 0.7)
}
