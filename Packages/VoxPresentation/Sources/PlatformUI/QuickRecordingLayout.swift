#if os(macOS)
import CoreGraphics
import UIShared

/// 快捷录音「灵动岛」布局常量。
///
/// 岛是**一个**形状，其尺寸/圆角是 `RecorderStatus` 的纯函数，随状态用弹簧形变
/// （收起 ↔ 展开，借鉴 Dynamic Island 的语法）。宿主浮窗固定为最大包络
/// （`panelWidth`×`panelHeight`），岛在其中居中变形，避免 NSPanel 反复重排。
///
/// 纯视觉状态语言（MY-1302）：展开态不再承载文字列，因此包络较旧版更紧凑。
public enum QuickRecordingLayout {
    /// 岛的尺寸包络（随状态形变）。
    public static func islandSize(for status: RecorderStatus) -> CGSize {
        switch status {
        case .idle:
            return CGSize(width: 72, height: 28)
        case .listening, .transcribing, .refining:
            return CGSize(width: 120, height: 54)
        case .done:
            return CGSize(width: 72, height: 44)
        case .error:
            return CGSize(width: 72, height: 44)
        }
    }

    /// 岛的圆角（随状态形变，恒为超椭圆胶囊感）。
    public static func islandCorner(for status: RecorderStatus) -> CGFloat {
        switch status {
        case .idle: return 14
        case .listening, .transcribing, .refining: return 22
        case .done: return 20
        case .error: return 20
        }
    }

    /// 宿主浮窗尺寸 = 最大包络 + 顶部呼吸留白，岛在其中变形。
    public static let panelWidth: CGFloat = 380
    public static let panelHeight: CGFloat = 132

    /// 浮窗距离屏幕顶部的偏移（更大表示更靠上）。
    public static let topInset: CGFloat = 120

    // MARK: - 展开态内部布局

    /// 波形簇宽度。
    public static let waveformWidth: CGFloat = 44
    /// 内容左内边距。
    public static let contentLeadingInset: CGFloat = 14
    /// 内容右内边距。
    public static let contentTrailingInset: CGFloat = 14
}
#endif
