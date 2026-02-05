import Foundation
import Combine

#if os(macOS)

/// 菜单栏视图状态协议 (macOS)
@MainActor
public protocol MenuBarViewState: ObservableObject {

    // MARK: - 状态属性

    /// 是否正在录音
    var isRecording: Bool { get }

    /// 录音时长
    var recordingDuration: TimeInterval { get }

    /// 当前文本内容
    var currentText: String { get }

    /// 当前文本长度
    var textLength: Int { get }

    /// 是否可以注入文本
    var canInject: Bool { get }

    /// 是否正在处理
    var isProcessing: Bool { get }

    /// 错误消息
    var errorMessage: String? { get }

    // MARK: - 操作

    /// 切换录音状态
    func toggleRecording() async

    /// 注入文本到聚焦的输入框
    func injectText() async

    /// 复制文本到剪贴板
    func copyToClipboard()

    /// 打开主窗口
    func openMainWindow()

    /// 打开设置窗口
    func openSettings()

    /// 退出应用
    func quit()

    /// 清除错误消息
    func clearError()
}

#endif
