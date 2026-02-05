import Foundation
import Combine

/// 菜单栏状态
public struct MenuBarState: Sendable, Equatable {
    /// 是否正在录音
    public let isRecording: Bool
    /// 是否正在处理
    public let isProcessing: Bool
    /// 当前文本长度
    public let textLength: Int

    public init(
        isRecording: Bool = false,
        isProcessing: Bool = false,
        textLength: Int = 0
    ) {
        self.isRecording = isRecording
        self.isProcessing = isProcessing
        self.textLength = textLength
    }

    public static let idle = MenuBarState()
}

/// 菜单栏服务协议 (macOS)
///
/// 提供菜单栏图标和弹出窗口管理。
public protocol MenuBarService: AnyObject, Sendable {

    /// 菜单栏图标是否可见
    var isVisible: Bool { get set }

    /// 弹出窗口是否显示
    var isPopoverShown: Bool { get }

    /// 更新菜单栏状态
    ///
    /// - Parameter state: 新状态
    func updateState(_ state: MenuBarState)

    /// 显示弹出窗口
    func showPopover()

    /// 隐藏弹出窗口
    func hidePopover()

    /// 切换弹出窗口显示状态
    func togglePopover()

    /// 弹出窗口显示状态变化发布者
    var popoverVisibilityPublisher: AnyPublisher<Bool, Never> { get }
}
