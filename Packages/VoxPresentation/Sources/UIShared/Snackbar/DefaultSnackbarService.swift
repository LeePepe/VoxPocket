import Foundation
import Combine

/// SnackbarService 默认实现
///
/// 管理 Snackbar 通知队列、自动消失计时器。线程安全，通过 @MainActor 确保 UI 绑定安全。
@MainActor
public final class DefaultSnackbarService: SnackbarService, ObservableObject {

    // MARK: - Published State

    @Published public private(set) var currentMessage: SnackbarMessage?

    public var currentMessagePublisher: AnyPublisher<SnackbarMessage?, Never> {
        $currentMessage.eraseToAnyPublisher()
    }

    // MARK: - Private

    private var queue: [SnackbarMessage] = []
    private var dismissTask: Task<Void, Never>?

    // MARK: - Init

    public init() {}

    // MARK: - SnackbarService

    public func show(_ message: SnackbarMessage) {
        // 新消息总是立即替换当前显示，确保每次调用都有视觉反馈
        // SnackbarOverlayView 通过 .id(message.id) 强制 SwiftUI 重建视图触发 transition 动画
        queue.removeAll()
        display(message)
    }

    public func dismiss(messageId: UUID?) {
        let targetId = messageId ?? currentMessage?.id
        guard let targetId, currentMessage?.id == targetId else { return }
        dismissCurrent()
    }

    public func clearQueue() {
        queue.removeAll()
    }

    // MARK: - Private

    private func display(_ message: SnackbarMessage) {
        dismissTask?.cancel()
        currentMessage = message
        scheduleAutoDismiss(for: message)
    }

    private func scheduleAutoDismiss(for message: SnackbarMessage) {
        guard let interval = message.duration.timeInterval else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.dismissCurrent()
        }
    }

    private func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        currentMessage = nil
        showNextIfAvailable()
    }

    private func showNextIfAvailable() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        display(next)
    }
}
