import Foundation
import Combine
import CoreModels
import LLMKit

/// 主编辑器视图状态协议
///
/// 定义编辑器视图所需的状态和操作接口。
@MainActor
public protocol EditorViewState: ObservableObject {

    // MARK: - 状态属性

    /// 当前文本内容
    var text: String { get }

    /// 是否正在录音
    var isRecording: Bool { get }

    /// 录音时长（秒）
    var recordingDuration: TimeInterval { get }

    /// 当前音频电平（0.0 - 1.0）
    var audioLevel: Float { get }

    /// 实时转录文本（临时，可能变化）
    var liveTranscription: String { get }

    /// 是否可以撤销
    var canUndo: Bool { get }

    /// 是否可以重做
    var canRedo: Bool { get }

    /// 是否正在 LLM 优化
    var isRefining: Bool { get }

    /// 错误消息
    var errorMessage: String? { get }

    /// 当前选中范围
    var selectedRange: NSRange { get set }

    /// 原始转录文本（录音停止后冻结，即使 refine 后也保留）
    var rawTranscription: String { get }

    /// 流式优化输出文本（refine 过程中实时更新）
    var streamingRefinedText: String { get }

    // MARK: - 录音操作

    /// 开始录音
    func startRecording() async

    /// 停止录音
    func stopRecording() async

    /// 切换录音状态
    func toggleRecording() async

    // MARK: - 编辑操作

    /// 撤销
    func undo()

    /// 重做
    func redo()

    /// 更新文本（响应用户编辑）
    ///
    /// - Parameters:
    ///   - newText: 新文本
    ///   - range: 被修改的范围
    func updateText(_ newText: String, range: NSRange)

    // MARK: - 优化操作

    /// 手动触发优化
    func refine() async

    /// 取消正在进行的优化
    func cancelRefinement()

    // MARK: - 清除操作

    /// 清除错误消息
    func clearError()

    /// 清空文本
    func clearText()
}
