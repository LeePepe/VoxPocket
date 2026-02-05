import Foundation
import Combine
import CoreModels
import TextHistory

/// 历史用例协议
///
/// 负责撤销/重做操作和历史状态管理。
public protocol HistoryUseCase: AnyObject, Sendable {

    /// 是否可以撤销
    var canUndo: Bool { get }

    /// 是否可以重做
    var canRedo: Bool { get }

    /// 可撤销状态发布者
    var canUndoPublisher: AnyPublisher<Bool, Never> { get }

    /// 可重做状态发布者
    var canRedoPublisher: AnyPublisher<Bool, Never> { get }

    /// 撤销次数
    var undoCount: Int { get }

    /// 重做次数
    var redoCount: Int { get }

    /// 执行撤销
    ///
    /// - Throws: `VoxError.cannotUndo` 如果已到达历史起点
    func undo() throws

    /// 执行重做
    ///
    /// - Throws: `VoxError.cannotRedo` 如果已到达历史末端
    func redo() throws

    /// 获取当前历史状态
    ///
    /// - Returns: 历史状态快照
    func getHistoryState() -> TextHistoryState

    /// 历史状态发布者
    var historyStatePublisher: AnyPublisher<TextHistoryState, Never> { get }

    /// 创建检查点
    ///
    /// 手动创建当前状态的检查点，用于快速恢复。
    func createCheckpoint()

    /// 清空历史
    ///
    /// 清除所有历史记录，保留当前文本。
    func clearHistory()
}
