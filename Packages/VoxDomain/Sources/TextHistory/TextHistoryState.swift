import Foundation

/// 文本历史的不可变状态快照
public struct TextHistoryState: Equatable, Sendable {
    /// 当前文本内容
    public let currentText: String
    /// 是否可以撤销
    public let canUndo: Bool
    /// 是否可以重做
    public let canRedo: Bool
    /// 可撤销的步数
    public let undoCount: Int
    /// 可重做的步数
    public let redoCount: Int

    public init(
        currentText: String,
        canUndo: Bool,
        canRedo: Bool,
        undoCount: Int,
        redoCount: Int
    ) {
        self.currentText = currentText
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.undoCount = undoCount
        self.redoCount = redoCount
    }

    /// 空状态
    public static let empty = TextHistoryState(
        currentText: "",
        canUndo: false,
        canRedo: false,
        undoCount: 0,
        redoCount: 0
    )
}
