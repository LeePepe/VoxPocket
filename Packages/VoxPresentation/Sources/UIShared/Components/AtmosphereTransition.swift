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

    /// 阶段入场的「呼吸」动力学。
    /// - 识别 / 转写 / 分析：一次 0→1→0 的柔和膨胀（吸气）+ 同色光晕，随即消散
    /// - 结果：从轻微放大收拢到静止（安定内收）+ 沉降的光晕
    /// - idle / error：静止
    ///
    /// - Returns: `scale` 整层缩放；`bloom` 中心光晕强度（0…~0.5）
    static func dynamics(
        status: RecorderStatus,
        transitionElapsed te: TimeInterval
    ) -> (scale: CGFloat, bloom: Double) {
        switch status {
        case .listening, .transcribing, .refining:
            // 半个正弦：0 → 峰值 → 0，约 0.9s 完成一次「吸气」
            let breath = sin(Double.pi * clamp(te / 0.9, min: 0, max: 1))
            return (1 + CGFloat(breath) * 0.018, breath * 0.5)
        case .done:
            // easeOut 收拢：入场 1.03 倍放大，安定回落到 1.0；光晕同步沉降
            let settle = easeOut(clamp(te / 0.85, min: 0, max: 1))
            return (1.03 - CGFloat(settle) * 0.03, (1 - settle) * 0.4)
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

    static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
