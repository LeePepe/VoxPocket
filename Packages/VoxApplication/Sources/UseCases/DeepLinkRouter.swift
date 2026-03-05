import Foundation
import Combine
import Observability

/// Deep Link 路由协议
///
/// 负责解析 URL Scheme 并分发对应的 `DeepLinkAction`。
/// Widget、Control Center 控件、Shortcuts 等入口统一通过此路由触发操作。
@MainActor
public protocol DeepLinkRouting: AnyObject {
    /// 待执行的 action（app 启动或唤起后消费）
    var pendingAction: DeepLinkAction? { get set }
    /// pendingAction 的发布者
    var pendingActionPublisher: AnyPublisher<DeepLinkAction?, Never> { get }
    /// 解析 URL 为 DeepLinkAction
    func resolve(_ url: URL) -> DeepLinkAction?
    /// 接收 URL，解析并设置 pendingAction
    func handle(_ url: URL)
}

/// 默认 Deep Link 路由
///
/// 解析 `voxpocket://` URL Scheme，将其转换为 `DeepLinkAction`。
///
/// 支持的 URL：
/// - `voxpocket://quickRecord` → 开始录音
/// - `voxpocket://newSession` → 新建会话
/// - `voxpocket://session/{uuid}` → 打开指定会话
@MainActor
public final class DefaultDeepLinkRouter: DeepLinkRouting, ObservableObject {

    @Published public var pendingAction: DeepLinkAction?
    private let logger: Logger

    public var pendingActionPublisher: AnyPublisher<DeepLinkAction?, Never> {
        $pendingAction.eraseToAnyPublisher()
    }

    public init(logger: Logger? = nil) {
        self.logger = logger ?? PrintLogger(subsystem: "DeepLinkRouter")
    }

    public func resolve(_ url: URL) -> DeepLinkAction? {
        guard url.scheme == "voxpocket" else { return nil }
        switch url.host {
        case "quickRecord":
            return .startRecording
        case "newSession":
            return .newSession
        case "session":
            if let id = UUID(uuidString: url.lastPathComponent) {
                return .openSession(id)
            }
            return nil
        default:
            return nil
        }
    }

    public func handle(_ url: URL) {
        if let action = resolve(url) {
            pendingAction = action
            logger.log(.debug, "Resolved deep link", context: [
                "url": url.absoluteString,
                "action": String(describing: action)
            ])
        } else {
            logger.log(.debug, "Unrecognized deep link URL", context: [
                "url": url.absoluteString
            ])
        }
    }
}
