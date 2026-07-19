import SwiftUI

/// 玻璃质感背景的配色模型：近白底 + 一组模糊彩色光团（blob），透过磨砂柔化成高级渐变。
///
/// 取代旧的「糖果色 baseGradient + 多层 directionalGradient + neumorphic 阴影」方案。
/// 六阶段共享同一「宝石柔调」和谐配方，仅主色心不同以区分阶段（多彩但不打架）。
/// 布局固定（5 个光团位置不变），阶段间只有颜色 morph，形状一致。

/// 单个光团：颜色 + 归一化位置 + 相对尺寸（相对画面最短边）。
struct AtmosphereBlob: Equatable {
    let color: Color
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
}

enum AtmosphereGlass {
    /// 近白玻璃底色。
    static let baseColor = Color(red: 0.97, green: 0.98, blue: 0.99)

    /// 固定的 5 个光团位置（四角 + 中心），阶段间不变 → 只 morph 颜色。
    private static let positions: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [
        (0.14, 0.20, 1.00),
        (0.84, 0.16, 0.95),
        (0.86, 0.82, 0.95),
        (0.18, 0.84, 0.92),
        (0.52, 0.50, 0.82)
    ]

    /// 某阶段的光团集合（宝石柔调，主色心随阶段偏移）。
    static func blobs(for status: RecorderStatus) -> [AtmosphereBlob] {
        zip(colors(for: status), positions).map { color, pos in
            AtmosphereBlob(color: color, x: pos.x, y: pos.y, scale: pos.s)
        }
    }

    /// 各阶段的 5 个光团颜色（和谐冷调多彩；error 为唯一暖调警示）。
    static func colors(for status: RecorderStatus) -> [Color] {
        switch status {
        case .idle:
            // 中性蓝灰多彩，最安静
            return [
                Color(red: 0.58, green: 0.72, blue: 0.78),
                Color(red: 0.56, green: 0.66, blue: 0.82),
                Color(red: 0.68, green: 0.64, blue: 0.82),
                Color(red: 0.80, green: 0.68, blue: 0.80),
                Color(red: 0.62, green: 0.72, blue: 0.82)
            ]
        case .listening:
            // 青绿主导（宝石柔调基调）
            return [
                Color(red: 0.32, green: 0.74, blue: 0.72),
                Color(red: 0.36, green: 0.58, blue: 0.88),
                Color(red: 0.58, green: 0.50, blue: 0.90),
                Color(red: 0.84, green: 0.54, blue: 0.82),
                Color(red: 0.46, green: 0.70, blue: 0.84)
            ]
        case .transcribing:
            // 蓝主导
            return [
                Color(red: 0.34, green: 0.56, blue: 0.90),
                Color(red: 0.44, green: 0.66, blue: 0.92),
                Color(red: 0.56, green: 0.52, blue: 0.90),
                Color(red: 0.40, green: 0.72, blue: 0.82),
                Color(red: 0.48, green: 0.60, blue: 0.92)
            ]
        case .refining:
            // 薰衣草紫主导
            return [
                Color(red: 0.58, green: 0.50, blue: 0.90),
                Color(red: 0.72, green: 0.54, blue: 0.90),
                Color(red: 0.84, green: 0.56, blue: 0.84),
                Color(red: 0.48, green: 0.54, blue: 0.90),
                Color(red: 0.66, green: 0.54, blue: 0.92)
            ]
        case .done:
            // 绿主导，安定
            return [
                Color(red: 0.34, green: 0.74, blue: 0.60),
                Color(red: 0.46, green: 0.78, blue: 0.66),
                Color(red: 0.40, green: 0.72, blue: 0.78),
                Color(red: 0.60, green: 0.80, blue: 0.58),
                Color(red: 0.44, green: 0.76, blue: 0.68)
            ]
        case .error:
            // 珊瑚红主导（唯一暖调，警示）
            return [
                Color(red: 0.90, green: 0.46, blue: 0.50),
                Color(red: 0.92, green: 0.56, blue: 0.52),
                Color(red: 0.86, green: 0.50, blue: 0.62),
                Color(red: 0.94, green: 0.62, blue: 0.54),
                Color(red: 0.88, green: 0.52, blue: 0.56)
            ]
        }
    }
}
