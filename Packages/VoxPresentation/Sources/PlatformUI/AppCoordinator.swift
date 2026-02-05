import Foundation
import Combine

/// 应用协调器协议
///
/// 负责协调应用级别的导航和状态管理。
@MainActor
public protocol AppCoordinator: ObservableObject {

    /// 当前活跃的会话 ID
    var activeSessionId: UUID? { get }

    /// 是否显示设置
    var isShowingSettings: Bool { get set }

    /// 是否显示会话列表
    var isShowingSessionList: Bool { get set }

    /// 导航到会话
    ///
    /// - Parameter id: 会话 ID
    func navigateToSession(_ id: UUID) async

    /// 创建新会话并导航
    func createAndNavigateToNewSession() async

    /// 处理 URL Scheme
    ///
    /// - Parameter url: URL
    func handleURL(_ url: URL) async

    /// 处理快捷方式
    ///
    /// - Parameter shortcut: 快捷方式标识符
    func handleShortcut(_ shortcut: String) async

    #if os(macOS)
    /// 显示主窗口
    func showMainWindow()

    /// 隐藏主窗口
    func hideMainWindow()
    #endif
}

/// URL Scheme 定义
public enum URLScheme {
    public static let scheme = "voxpocket"

    public enum Host: String {
        case record = "record"
        case newSession = "new"
        case openSession = "session"
        case settings = "settings"
    }
}
