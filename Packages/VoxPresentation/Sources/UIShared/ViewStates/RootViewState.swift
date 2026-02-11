import Foundation
import Combine
import CoreModels

/// 根视图状态协议
///
/// 定义应用根视图所需的状态和操作接口，组合子 ViewModel。
@MainActor
public protocol RootViewState: ObservableObject {

    associatedtype SessionList: SessionListViewState
    associatedtype Editor: EditorViewState

    // MARK: - 子 ViewModel

    /// 会话列表状态
    var sessionListState: SessionList { get }

    /// 编辑器状态
    var editorState: Editor { get }

    // MARK: - 导航状态

    /// 当前录音器状态
    var recorderStatus: RecorderStatus { get }

    /// 抽屉是否打开
    var isDrawerOpen: Bool { get set }

    /// 是否显示原始转写 Sheet
    var showRawSheet: Bool { get set }

    /// 导航路径
    var navigationPath: [Route] { get set }

    // MARK: - 操作

    /// 选择会话
    func selectSession(_ id: UUID)

    /// 导航到 Me 页面
    func navigateToMe()

    /// 切换抽屉
    func toggleDrawer()

    /// 创建新会话并返回主页
    func createNewSession()
}
