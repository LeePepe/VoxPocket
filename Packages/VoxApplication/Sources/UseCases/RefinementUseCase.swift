import Foundation
import Combine
import LLMKit

/// 优化状态
public enum RefinementState: Equatable, Sendable {
    /// 空闲
    case idle
    /// 优化中
    case refining(progress: String)
    /// 已完成
    case completed
    /// 发生错误
    case error(String)

    /// 是否正在优化
    public var isRefining: Bool {
        if case .refining = self {
            return true
        }
        return false
    }
}

/// 优化事件
///
/// 统一流式优化过程中的状态变更和数据块。
public enum RefinementEvent: Sendable {
    /// 状态变更
    case state(RefinementState)
    /// 文本块
    case chunk(String)
}

/// LLM 优化用例协议
///
/// 负责调用 LLM 服务对文本进行优化，并将结果作为可撤销的变更提交。
public protocol RefinementUseCase: AnyObject, Sendable {

    /// 当前优化状态
    var state: RefinementState { get }

    /// 状态变更发布者
    var statePublisher: AnyPublisher<RefinementState, Never> { get }

    /// 执行优化
    ///
    /// 优化当前文本，并将结果提交到历史。
    ///
    /// - Parameters:
    ///   - customPrompt: 自定义提示词（可选）
    /// - Throws: LLM 服务错误
    func refine(customPrompt: String?) async throws

    /// 优化选中的文本
    ///
    /// - Parameters:
    ///   - range: 选中的文本范围
    ///   - customPrompt: 自定义提示词
    /// - Throws: LLM 服务错误
    func refineSelection(range: NSRange, customPrompt: String?) async throws

    /// 流式优化
    ///
    /// 实时返回优化结果和状态变更，用于显示打字机效果。
    ///
    /// - Parameters:
    ///   - customPrompt: 自定义提示词
    /// - Returns: 异步事件流（包含状态和文本块）
    func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error>

    /// 取消当前优化
    func cancel()

    /// 检查 LLM 服务是否已配置
    var isConfigured: Bool { get }
}
