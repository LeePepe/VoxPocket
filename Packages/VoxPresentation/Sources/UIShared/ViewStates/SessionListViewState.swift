import Foundation
import Combine
import CoreModels

/// 会话列表视图状态协议
@MainActor
public protocol SessionListViewState: ObservableObject {

    // MARK: - 状态属性

    /// 会话列表
    var sessions: [Session] { get }

    /// 是否正在加载
    var isLoading: Bool { get }

    /// 当前选中的会话 ID
    var selectedSessionId: UUID? { get set }

    /// 搜索关键词
    var searchQuery: String { get set }

    /// 过滤后的会话列表
    var filteredSessions: [Session] { get }

    /// 错误消息
    var errorMessage: String? { get }

    // MARK: - 操作

    /// 加载会话列表
    func loadSessions() async

    /// 创建新会话
    func createSession() async

    /// 删除会话
    ///
    /// - Parameter id: 会话 ID
    func deleteSession(_ id: UUID) async

    /// 删除所有会话
    func deleteAllSessions() async

    /// 选择会话
    ///
    /// - Parameter id: 会话 ID
    func selectSession(_ id: UUID) async

    /// 刷新会话列表
    func refresh() async

    /// 清除错误消息
    func clearError()
}
