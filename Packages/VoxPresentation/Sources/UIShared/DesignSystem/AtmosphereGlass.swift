import SwiftUI

/// 主 UI 与快捷录音共享的纯配色模型，归属 DesignSystem；视图只消费颜色与位置。
///
/// 取代旧的「糖果色 baseGradient + 多层 directionalGradient + neumorphic 阴影」方案。
/// 六阶段共享同一「宝石柔调」和谐配方，仅主色心不同以区分阶段（多彩但不打架）。
/// 布局固定（5 个光团位置不变），阶段间只有颜色 morph，形状一致。

/// 单个光团：颜色 + 归一化位置 + 相对尺寸（相对统一坐标画布）。
struct AtmosphereBlob: Equatable {
    let color: Color
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
}

enum AtmosphereGlass {
    /// 近白玻璃底色。
    static let baseColor = Color(.sRGB, red: 0.97, green: 0.98, blue: 0.99, opacity: 1)
    static let transitionDuration: TimeInterval = 0.9

    static func baseColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.dark.palette.backgroundBase : baseColor
    }

    static func washOpacity(for scheme: ColorScheme, energy: Double) -> Double {
        let bounded = energy.isFinite ? min(1, max(0, energy)) : 0
        return scheme == .dark ? 0.24 + bounded * 0.04 : 0.72 + bounded * 0.14
    }

    static func allowsAtmosphere(reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
        !reduceTransparency && !increasedContrast
    }

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

    /// 各阶段的 5 个光团 sRGB 分量（和谐冷调多彩；error 为唯一暖调警示）。
    static func colorComponents(for status: RecorderStatus) -> [(r: Double, g: Double, b: Double)] {
        switch status {
        case .idle:
            // 中性蓝灰多彩，最安静
            return [
                (0.58, 0.72, 0.78),
                (0.56, 0.66, 0.82),
                (0.68, 0.64, 0.82),
                (0.80, 0.68, 0.80),
                (0.62, 0.72, 0.82)
            ]
        case .listening:
            // 青绿主导（宝石柔调基调）
            return [
                (0.32, 0.74, 0.72),
                (0.36, 0.58, 0.88),
                (0.58, 0.50, 0.90),
                (0.84, 0.54, 0.82),
                (0.46, 0.70, 0.84)
            ]
        case .transcribing:
            // 蓝主导
            return [
                (0.34, 0.56, 0.90),
                (0.44, 0.66, 0.92),
                (0.56, 0.52, 0.90),
                (0.40, 0.72, 0.82),
                (0.48, 0.60, 0.92)
            ]
        case .refining:
            // 薰衣草紫主导
            return [
                (0.58, 0.50, 0.90),
                (0.72, 0.54, 0.90),
                (0.84, 0.56, 0.84),
                (0.48, 0.54, 0.90),
                (0.66, 0.54, 0.92)
            ]
        case .done:
            // 绿主导，安定
            return [
                (0.34, 0.74, 0.60),
                (0.46, 0.78, 0.66),
                (0.40, 0.72, 0.78),
                (0.60, 0.80, 0.58),
                (0.44, 0.76, 0.68)
            ]
        case .error:
            // 珊瑚红主导（唯一暖调，警示）
            return [
                (0.90, 0.46, 0.50),
                (0.92, 0.56, 0.52),
                (0.86, 0.50, 0.62),
                (0.94, 0.62, 0.54),
                (0.88, 0.52, 0.56)
            ]
        }
    }

    /// 各阶段的 5 个光团颜色（和谐冷调多彩；error 为唯一暖调警示）。
    static func colors(for status: RecorderStatus) -> [Color] {
        colorComponents(for: status).map { comp in
            Color(.sRGB, red: comp.r, green: comp.g, blue: comp.b, opacity: 1)
        }
    }

    static func normalizedPositions() -> [(x: CGFloat, y: CGFloat, s: CGFloat)] {
        positions
    }
}
