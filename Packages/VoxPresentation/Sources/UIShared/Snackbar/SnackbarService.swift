import Foundation
import Combine

/// Snackbar 通知服务协议
///
/// 负责管理全局 Snackbar 通知的显示、排队和生命周期。
/// 采用队列机制确保通知按优先级有序展示。
@MainActor
public protocol SnackbarService: AnyObject {

    /// 当前显示的通知（用于 SwiftUI 绑定）
    var currentMessage: SnackbarMessage? { get }

    /// 当前消息发布者（用于 SwiftUI 绑定）
    var currentMessagePublisher: AnyPublisher<SnackbarMessage?, Never> { get }

    /// 显示一条通知
    ///
    /// - Parameter message: 要显示的通知配置
    /// - Note: 根据优先级决定是立即显示还是排队等待
    func show(_ message: SnackbarMessage)

    /// 关闭指定的通知
    ///
    /// - Parameter messageId: 要关闭的通知 ID，nil 表示关闭当前显示的通知
    func dismiss(messageId: UUID?)

    /// 清空所有排队的通知
    func clearQueue()
}

// MARK: - 便捷扩展

public extension SnackbarService {

    /// 显示信息通知
    func showInfo(_ message: String, action: SnackbarAction? = nil) {
        show(SnackbarMessage(type: .info, message: message, action: action))
    }

    /// 显示成功通知
    func showSuccess(_ message: String) {
        show(SnackbarMessage(type: .success, message: message))
    }

    /// 显示警告通知
    func showWarning(_ message: String, action: SnackbarAction? = nil) {
        show(SnackbarMessage(type: .warning, message: message, action: action))
    }

    /// 显示错误通知
    func showError(_ message: String, action: SnackbarAction? = nil) {
        show(SnackbarMessage(
            type: .error,
            message: message,
            priority: .high,
            action: action
        ))
    }

    /// 显示带重试操作的错误通知
    func showRetryableError(_ message: String, retryHandler: @escaping @Sendable () -> Void) {
        show(SnackbarMessage(
            type: .error,
            message: message,
            priority: .high,
            duration: .long,
            action: SnackbarAction(title: "重试", handler: retryHandler)
        ))
    }

    /// 关闭当前通知
    func dismiss() {
        dismiss(messageId: nil)
    }
}
