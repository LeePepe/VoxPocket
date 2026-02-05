import Foundation
import Combine
import CoreModels
import TextHistory

/// 历史用例最小实现
///
/// 暂不实现完整 undo/redo，仅提供协议 stub。
public final class DefaultHistoryUseCase: HistoryUseCase, @unchecked Sendable {

    public var canUndo: Bool { false }
    public var canRedo: Bool { false }

    public var canUndoPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    public var canRedoPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    public var undoCount: Int { 0 }
    public var redoCount: Int { 0 }

    public var historyStatePublisher: AnyPublisher<TextHistoryState, Never> {
        Just(TextHistoryState.empty).eraseToAnyPublisher()
    }

    public init() {}

    public func undo() throws {
        throw NSError(domain: "DefaultHistoryUseCase", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Undo 暂未实现"])
    }

    public func redo() throws {
        throw NSError(domain: "DefaultHistoryUseCase", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Redo 暂未实现"])
    }

    public func getHistoryState() -> TextHistoryState {
        .empty
    }

    public func createCheckpoint() {}

    public func clearHistory() {}
}
