#if os(macOS)
import CoreGraphics

/// 快速录音浮窗布局常量。
public enum QuickRecordingLayout {
    /// 胶囊主体尺寸。
    public static let pillWidth: CGFloat = 132
    public static let pillHeight: CGFloat = 34

    /// 面板尺寸（包含主体周围留白 + 阴影空间）。
    public static let panelWidth: CGFloat = 164
    public static let panelHeight: CGFloat = 58

    /// 浮窗距离屏幕顶部的偏移（更大表示更靠上）。
    public static let topInset: CGFloat = 120

    /// 面板圆角。
    public static let panelCornerRadius: CGFloat = 32

    /// 实时转写文字左右内边距。
    public static let textHorizontalInset: CGFloat = 12

    /// 左侧旧文字渐出区域宽度。
    public static let textLeftFadeWidth: CGFloat = 24
}
#endif
