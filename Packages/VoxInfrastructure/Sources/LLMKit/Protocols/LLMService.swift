import Foundation
import Combine

/// LLM 服务协议
///
/// 管理多个 LLM 提供者，提供统一的接口用于文本生成任务。
/// 支持通用的文本完成（completion）以及特化的优化（refinement）功能。
public protocol LLMService: AnyObject, Sendable {

    /// 可用的提供者类型列表
    var availableProviders: [LLMProviderType] { get }

    /// 当前使用的提供者
    var currentProvider: LLMProvider? { get }

    /// 当前提供者类型
    var currentProviderType: LLMProviderType? { get }

    /// 设置当前提供者
    ///
    /// - Parameter config: 提供者配置
    /// - Throws: 配置无效时抛出错误
    func setProvider(_ config: LLMProviderConfig) throws

    // MARK: - 通用文本完成

    /// 通用文本完成
    ///
    /// 使用当前 LLM 提供者生成文本响应。适用于任何需要 LLM 生成文本的场景。
    ///
    /// - Parameter prompt: 输入提示词
    /// - Returns: LLM 生成的响应文本
    /// - Throws: `VoxError.llmProviderNotConfigured` 如果未配置提供者
    func complete(prompt: String) async throws -> String

    /// 流式文本完成
    ///
    /// 使用流式输出的方式生成文本响应。
    ///
    /// - Parameter prompt: 输入提示词
    /// - Returns: 异步文本流
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error>

    // MARK: - 文本优化（便捷方法）

    /// 执行文本优化
    ///
    /// 针对文本优化场景的便捷方法，内部调用 complete 并封装结果。
    ///
    /// - Parameter request: 优化请求
    /// - Returns: 优化响应
    /// - Throws: `VoxError.llmProviderNotConfigured` 如果未配置提供者
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse

    /// 流式文本优化
    ///
    /// - Parameter request: 优化请求
    /// - Returns: 异步文本流
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error>

    /// 取消当前请求
    func cancel()

    /// 验证当前提供者配置
    ///
    /// - Returns: 配置是否有效
    func validateCurrentProvider() async -> Bool
}
