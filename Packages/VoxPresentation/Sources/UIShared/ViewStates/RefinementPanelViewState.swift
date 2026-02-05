import Foundation
import Combine
import LLMKit

/// 优化面板视图状态协议
@MainActor
public protocol RefinementPanelViewState: ObservableObject {

    // MARK: - 状态属性

    /// 自定义提示词
    var customPrompt: String { get set }

    /// 是否正在优化
    var isRefining: Bool { get }

    /// 流式输出的文本（用于实时显示）
    var streamingText: String { get }

    /// 优化进度描述
    var progressMessage: String { get }

    /// 错误消息
    var errorMessage: String? { get }

    /// 是否已配置 LLM 服务
    var isConfigured: Bool { get }

    // MARK: - 操作

    /// 执行优化
    func refine() async

    /// 优化选中的文本
    ///
    /// - Parameter range: 选中范围
    func refineSelection(range: NSRange) async

    /// 取消优化
    func cancel()

    /// 清除错误消息
    func clearError()

    /// 使用流式输出执行优化
    func refineWithStreaming() async
}
