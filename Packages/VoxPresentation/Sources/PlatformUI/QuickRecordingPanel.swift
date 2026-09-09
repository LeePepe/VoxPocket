#if os(macOS)
import AppKit

/// 快捷岛的 AppKit 宿主，屏幕位置由真实刘海几何决定。
@MainActor
public final class QuickRecordingPanel: NSPanel {
    public var placement: QuickRecordingPlacement = .floating

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let constrained = super.constrainFrameRect(frameRect, to: screen)
        guard let screen else { return constrained }
        return resolvedFrame(proposed: frameRect, constrained: constrained,
                             screenFrame: screen.frame, screenHasCamera: screen.safeAreaInsets.top > 0)
    }

    func resolvedFrame(proposed: CGRect, constrained: CGRect, screenFrame: CGRect, screenHasCamera: Bool) -> CGRect {
        // 仅保留当前真实刘海的合法贴顶位置；外接屏、移动、越界与变尺寸仍交给 AppKit。
        guard placement.isAttached, screenHasCamera, screenFrame.contains(proposed),
              proposed == placement.panelFrame, abs(proposed.maxY - screenFrame.maxY) < 1 else {
            return constrained
        }
        return proposed
    }
}
#endif
