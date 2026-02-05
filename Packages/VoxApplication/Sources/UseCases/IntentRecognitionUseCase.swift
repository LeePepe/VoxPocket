import Foundation
import LLMKit

/// 意图识别用例协议
///
/// 负责分析用户的语音转录文本，识别用户的真实意图。
/// 支持混合策略：优先使用快速的规则匹配，复杂情况使用 LLM 识别。
public protocol IntentRecognitionUseCase: AnyObject, Sendable {

    /// 识别用户意图
    ///
    /// - Parameter text: 转录的文本
    /// - Returns: 识别出的意图结果
    /// - Throws: 识别过程中的错误
    func recognizeIntent(from text: String) async throws -> IntentRecognitionResult

    /// 仅使用规则匹配识别意图（不调用 LLM）
    ///
    /// - Parameter text: 转录的文本
    /// - Returns: 如果匹配成功返回意图结果，否则返回 nil
    func quickRecognize(from text: String) -> IntentRecognitionResult?

    /// 是否启用 LLM 增强识别
    ///
    /// 当规则匹配失败时，是否使用 LLM 进行深度识别
    var isLLMEnhancementEnabled: Bool { get }
}
