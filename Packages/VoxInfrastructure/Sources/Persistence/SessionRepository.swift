import Foundation
import Combine
import CoreModels

/// 会话仓储协议
///
/// 负责会话实体的持久化操作。
public protocol SessionRepository: AnyObject, Sendable {

    /// 获取所有会话
    ///
    /// - Returns: 会话数组，按更新时间降序排列
    func fetchAll() async throws -> [Session]

    /// 根据 ID 获取会话
    ///
    /// - Parameter id: 会话 ID
    /// - Returns: 会话实体，如果不存在则返回 nil
    func fetch(by id: UUID) async throws -> Session?

    /// 保存会话
    ///
    /// 如果会话已存在则更新，否则创建新会话。
    ///
    /// - Parameter session: 要保存的会话
    func save(_ session: Session) async throws

    /// 删除会话
    ///
    /// - Parameter session: 要删除的会话
    func delete(_ session: Session) async throws

    /// 删除会话（通过 ID）
    ///
    /// - Parameter id: 要删除的会话 ID
    func delete(by id: UUID) async throws

    /// 观察会话列表变化
    ///
    /// - Returns: 发布会话列表变化的发布者
    func observe() -> AnyPublisher<[Session], Error>

    /// 观察单个会话变化
    ///
    /// - Parameter id: 会话 ID
    /// - Returns: 发布会话变化的发布者
    func observe(id: UUID) -> AnyPublisher<Session?, Error>

    /// 搜索会话
    ///
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的会话数组
    func search(query: String) async throws -> [Session]
}
