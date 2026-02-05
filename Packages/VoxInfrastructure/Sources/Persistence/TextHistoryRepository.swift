import Foundation
import CoreModels
import TextHistory

/// 文本历史仓储协议
///
/// 负责补丁和检查点的持久化操作。
public protocol TextHistoryRepository: AnyObject, Sendable {

    /// 获取会话的所有补丁
    ///
    /// - Parameter sessionId: 会话 ID
    /// - Returns: 补丁数组，按时间戳升序排列
    func fetchPatches(for sessionId: UUID) async throws -> [Patch]

    /// 获取指定检查点之后的补丁
    ///
    /// - Parameters:
    ///   - sessionId: 会话 ID
    ///   - afterIndex: 检查点索引
    /// - Returns: 补丁数组
    func fetchPatches(for sessionId: UUID, afterIndex: Int) async throws -> [Patch]

    /// 保存单个补丁
    ///
    /// - Parameters:
    ///   - patch: 要保存的补丁
    ///   - sessionId: 会话 ID
    func savePatch(_ patch: Patch, for sessionId: UUID) async throws

    /// 批量保存补丁
    ///
    /// - Parameters:
    ///   - patches: 要保存的补丁数组
    ///   - sessionId: 会话 ID
    func savePatches(_ patches: [Patch], for sessionId: UUID) async throws

    /// 获取最新检查点
    ///
    /// - Parameter sessionId: 会话 ID
    /// - Returns: 最新的检查点，如果没有则返回 nil
    func fetchLatestCheckpoint(for sessionId: UUID) async throws -> Checkpoint?

    /// 获取所有检查点
    ///
    /// - Parameter sessionId: 会话 ID
    /// - Returns: 检查点数组，按索引升序排列
    func fetchCheckpoints(for sessionId: UUID) async throws -> [Checkpoint]

    /// 保存检查点
    ///
    /// - Parameters:
    ///   - checkpoint: 要保存的检查点
    ///   - sessionId: 会话 ID
    func saveCheckpoint(_ checkpoint: Checkpoint, for sessionId: UUID) async throws

    /// 清理旧补丁
    ///
    /// 删除指定检查点之前的所有补丁以节省存储空间。
    ///
    /// - Parameters:
    ///   - checkpoint: 基准检查点
    ///   - sessionId: 会话 ID
    func prunePatches(before checkpoint: Checkpoint, for sessionId: UUID) async throws

    /// 删除会话的所有历史数据
    ///
    /// - Parameter sessionId: 会话 ID
    func deleteHistory(for sessionId: UUID) async throws
}
