import CoreGraphics
import Foundation

/// 氛围背景「阶段流转」的纯节奏函数集合。
///
/// 与 SwiftUI / 逐帧渲染解耦，全部为确定性纯函数，便于单元测试守护动效曲线：
/// - 交叉淡出（crossfade）：色彩语言在阶段间 morph 而非硬切
/// - 呼吸动力学（dynamics）：入场膨胀（吸气）/ 完成内收（安定）+ 同色光晕
///
/// 设计目标（用户要求「更大胆更高级」且「尊重 Reduce Motion」）：
/// 呼吸/内收只作用于整层 scale + 一层 additive 光晕，不驱动布局属性；
/// reduceMotion 的判定留在视图层，本类只描述「开启动效时」的曲线。
enum AtmosphereTransition {
    /// 交叉淡出进度 0→1，采用 smoothstep（Hermite）过渡，比线性更有机。
    /// - Parameters:
    ///   - elapsed: 自阶段切换起经过的秒数
    ///   - duration: 交叉淡出窗口时长（秒）
    static func crossfade(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return smoothstep(clamp(elapsed / duration, min: 0, max: 1))
    }

    /// 阶段入场的「呼吸」动力学（less is more：以柔光为主，克制缩放）。
    /// - 识别 / 转写 / 分析：整层不缩放，仅一层极淡的中心柔光 0→峰→0（气息感）
    /// - 结果：从极轻微放大（1.015）收拢到静止 + 沉降柔光（安定内收）
    /// - idle / error：静止
    ///
    /// - Returns: `scale` 整层缩放；`bloom` 中心光晕强度（0…~0.26）
    static func dynamics(
        status: RecorderStatus,
        transitionElapsed te: TimeInterval
    ) -> (scale: CGFloat, bloom: Double) {
        switch status {
        case .listening, .transcribing, .refining:
            // 半个正弦：0 → 峰值 → 0，约 1.0s 完成一次「气息」。不缩放，纯柔光。
            let breath = sin(Double.pi * clamp(te / 1.0, min: 0, max: 1))
            return (1, breath * 0.26)
        case .done:
            // easeOut 收拢：入场 1.015 倍极轻微放大，安定回落到 1.0；柔光同步沉降
            let settle = easeOut(clamp(te / 0.9, min: 0, max: 1))
            return (1.015 - CGFloat(settle) * 0.015, (1 - settle) * 0.2)
        case .idle, .error:
            return (1, 0)
        }
    }

    // MARK: - 基础曲线

    /// 平滑阶跃（Hermite）：3t² − 2t³，两端一阶导为 0，比线性更「有机」。
    static func smoothstep(_ t: Double) -> Double {
        let x = clamp(t, min: 0, max: 1)
        return x * x * (3 - 2 * x)
    }

    /// 三次 easeOut：1 − (1 − t)³，起步快、收尾稳，用于「安定内收」。
    static func easeOut(_ t: Double) -> Double {
        let x = clamp(t, min: 0, max: 1)
        return 1 - pow(1 - x, 3)
    }

    // MARK: - 弹簧积分（audioLevel 的「活呼吸」）

    /// 显式弹簧一步积分（半隐式欧拉）。用于把实时音频电平从「笨低通 EMA」升级为
    /// velocity-aware、可继承速度的物理呼吸：声音骤起有冲劲、停顿柔和 settle。
    ///
    /// 由渲染帧（TimelineView 的 context.date）以真实 dt 驱动 → display-synced，
    /// 消除原 EMA「只在音频回调更新、与渲染帧不同步」的双时钟问题。
    ///
    /// - Parameters:
    ///   - position: 当前值
    ///   - velocity: 当前速度
    ///   - target: 目标值（当前音频电平）
    ///   - dt: 距上一帧的秒数（内部夹到 [0, 1/30] 防大跳导致发散）
    ///   - stiffness: 刚度 k（越大越快追上目标）
    ///   - damping: 阻尼 c（临界阻尼 ≈ 2√k；略欠阻尼给一丝生命感的过冲）
    /// - Returns: 步进后的 (position, velocity)
    static func springStep(
        position: Double,
        velocity: Double,
        target: Double,
        dt: Double,
        stiffness: Double = 170,
        damping: Double = 22
    ) -> (position: Double, velocity: Double) {
        // 夹住 dt：切后台/掉帧回来时 dt 可能很大，会让显式积分发散
        let h = clamp(dt, min: 0, max: 1.0 / 30.0)
        guard h > 0 else { return (position, velocity) }
        let accel = -stiffness * (position - target) - damping * velocity
        let newVelocity = velocity + accel * h
        let newPosition = position + newVelocity * h
        return (newPosition, newVelocity)
    }

    static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
