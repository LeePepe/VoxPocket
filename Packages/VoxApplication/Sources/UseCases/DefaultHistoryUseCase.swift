import Foundation
import Combine
import CoreModels
import TextHistory

/// 快照式 undo/redo 历史用例
///
/// 监听 `EditingUseCase.currentTextPublisher` 自动记录文本快照，
/// 支持撤销/重做操作。使用 `isRestoring` 标志避免 undo/redo 触发的
/// 文本变更被重复记录。
public final class DefaultHistoryUseCase: HistoryUseCase, @unchecked Sendable {

    private let editingUseCase: EditingUseCase

    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private var currentText: String = ""

    /// 防止 undo/redo 引起的文本变更被再次记录
    private var isRestoring = false

    private var cancellables = Set<AnyCancellable>()

    private let canUndoSubject = CurrentValueSubject<Bool, Never>(false)
    private let canRedoSubject = CurrentValueSubject<Bool, Never>(false)
    private let historyStateSubject = CurrentValueSubject<TextHistoryState, Never>(.empty)

    // MARK: - HistoryUseCase

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var canUndoPublisher: AnyPublisher<Bool, Never> {
        canUndoSubject.eraseToAnyPublisher()
    }

    public var canRedoPublisher: AnyPublisher<Bool, Never> {
        canRedoSubject.eraseToAnyPublisher()
    }

    public var undoCount: Int { undoStack.count }
    public var redoCount: Int { redoStack.count }

    public var historyStatePublisher: AnyPublisher<TextHistoryState, Never> {
        historyStateSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    public init(editing: EditingUseCase) {
        self.editingUseCase = editing
        self.currentText = editing.currentText

        editing.currentTextPublisher
            .removeDuplicates()
            .sink { [weak self] newText in
                self?.recordIfNeeded(newText)
            }
            .store(in: &cancellables)
    }

    // MARK: - Record

    private func recordIfNeeded(_ newText: String) {
        guard !isRestoring else { return }
        guard newText != currentText else { return }

        undoStack.append(currentText)
        redoStack.removeAll()
        currentText = newText
        publishState()
    }

    // MARK: - Undo / Redo

    public func undo() throws {
        guard let previous = undoStack.popLast() else {
            throw NSError(domain: "DefaultHistoryUseCase", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "没有可撤销的操作"])
        }
        redoStack.append(currentText)
        currentText = previous

        isRestoring = true
        try? editingUseCase.replaceAll(with: previous)
        isRestoring = false

        publishState()
    }

    public func redo() throws {
        guard let next = redoStack.popLast() else {
            throw NSError(domain: "DefaultHistoryUseCase", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "没有可重做的操作"])
        }
        undoStack.append(currentText)
        currentText = next

        isRestoring = true
        try? editingUseCase.replaceAll(with: next)
        isRestoring = false

        publishState()
    }

    public func getHistoryState() -> TextHistoryState {
        TextHistoryState(
            currentText: currentText,
            canUndo: canUndo,
            canRedo: canRedo,
            undoCount: undoCount,
            redoCount: redoCount
        )
    }

    public func createCheckpoint() {
        // 快照模式下无需额外检查点
    }

    public func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        currentText = editingUseCase.currentText
        publishState()
    }

    // MARK: - Private

    private func publishState() {
        canUndoSubject.send(canUndo)
        canRedoSubject.send(canRedo)
        historyStateSubject.send(getHistoryState())
    }
}
