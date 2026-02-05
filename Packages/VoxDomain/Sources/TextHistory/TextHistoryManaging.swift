import Foundation
import Combine
import CoreModels

/// 文本历史管理器协议
///
/// 负责管理文本的变更历史，支持撤销/重做操作。
/// 采用补丁（Patch）机制记录每次变更，确保操作的可逆性。
public protocol TextHistoryManaging: AnyObject, Sendable {

    /// 当前状态快照
    var state: TextHistoryState { get }

    /// 状态变更发布者（用于 SwiftUI 绑定）
    var statePublisher: AnyPublisher<TextHistoryState, Never> { get }

    /// 应用新的补丁
    ///
    /// - Parameter patch: 要应用的补丁
    /// - Throws: `VoxError.patchApplicationFailed` 如果补丁无法应用
    func apply(_ patch: Patch) throws

    /// 批量应用补丁
    ///
    /// - Parameter patches: 要应用的补丁数组
    /// - Throws: `VoxError.patchApplicationFailed` 如果任何补丁无法应用
    func apply(_ patches: [Patch]) throws

    /// 撤销最近的一次变更
    ///
    /// - Returns: 被撤销的补丁，如果无法撤销则返回 nil
    /// - Throws: `VoxError.cannotUndo` 如果已到达历史起点
    @discardableResult
    func undo() throws -> Patch?

    /// 重做最近撤销的变更
    ///
    /// - Returns: 被重做的补丁，如果无法重做则返回 nil
    /// - Throws: `VoxError.cannotRedo` 如果已到达历史末端
    @discardableResult
    func redo() throws -> Patch?

    /// 创建当前状态的检查点
    ///
    /// - Returns: 新创建的检查点
    func createCheckpoint() -> Checkpoint

    /// 从检查点恢复状态
    ///
    /// - Parameter checkpoint: 要恢复的检查点
    /// - Throws: `VoxError.checkpointCorrupted` 如果检查点数据无效
    func restore(from checkpoint: Checkpoint) throws

    /// 清空所有历史，重置为初始状态
    func reset()

    /// 清空所有历史，并设置初始文本
    ///
    /// - Parameter initialText: 初始文本内容
    func reset(with initialText: String)
}
