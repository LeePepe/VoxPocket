import Foundation
import Combine
import CoreModels

/// 会话用例协议
///
/// 负责会话的创建、加载、保存和删除。
public protocol SessionUseCase: AnyObject, Sendable {

    /// 当前会话
    var currentSession: Session? { get }

    /// 当前会话发布者
    var currentSessionPublisher: AnyPublisher<Session?, Never> { get }

    /// 创建新会话
    ///
    /// - Parameter title: 会话标题（可选，默认使用时间戳）
    /// - Returns: 新创建的会话
    func createSession(title: String?) async throws -> Session

    /// 加载会话
    ///
    /// 加载指定会话及其历史记录。
    ///
    /// - Parameter id: 会话 ID
    /// - Throws: `VoxError.sessionNotFound` 如果会话不存在
    func loadSession(_ id: UUID) async throws

    /// 保存当前会话
    ///
    /// 保存当前会话的状态和历史。
    func saveCurrentSession() async throws

    /// 获取所有会话
    ///
    /// - Returns: 会话数组，按更新时间降序排列
    func fetchAllSessions() async throws -> [Session]

    /// 删除会话
    ///
    /// - Parameter id: 要删除的会话 ID
    func deleteSession(_ id: UUID) async throws

    /// 更新会话标题
    ///
    /// - Parameters:
    ///   - id: 会话 ID
    ///   - title: 新标题
    func updateSessionTitle(_ id: UUID, title: String) async throws

    /// 观察会话列表变化
    var sessionsPublisher: AnyPublisher<[Session], Error> { get }

    /// 关闭当前会话
    ///
    /// 保存并关闭当前会话。
    func closeCurrentSession() async throws

    /// 保存已完成的录音会话
    ///
    /// 创建并持久化一个包含转录文本的会话。
    ///
    /// - Parameters:
    ///   - title: 会话标题（可选，默认从内容生成）
    ///   - rawText: 原始转录文本
    ///   - refinedText: LLM 优化后的文本
    /// - Returns: 创建的会话
    @discardableResult
    func saveCompletedSession(title: String?, rawText: String, refinedText: String) async throws -> Session
}
