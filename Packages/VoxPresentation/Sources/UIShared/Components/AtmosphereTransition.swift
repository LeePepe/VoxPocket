import CoreGraphics
import Foundation

/// 氛围背景「阶段流转」的纯节奏函数集合。
///
/// 与 SwiftUI / 逐帧渲染解耦，全部为确定性纯函数，便于单元测试守护动效曲线：
/// - 交叉淡出（crossfade）：色彩语言在阶段间 morph 而非硬切
/// - 弹簧积分（springStep）：audioLevel 的 velocity-aware 呼吸
///
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

    // MARK: - 基础曲线

    /// 平滑阶跃（Hermite）：3t² − 2t³，两端一阶导为 0，比线性更「有机」。用于交叉淡出。
    static func smoothstep(_ t: Double) -> Double {
        let x = clamp(t, min: 0, max: 1)
        return x * x * (3 - 2 * x)
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
