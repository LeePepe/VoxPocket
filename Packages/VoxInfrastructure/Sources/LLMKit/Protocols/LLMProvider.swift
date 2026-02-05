import Foundation

/// LLM 提供者类型
public enum LLMProviderType: String, CaseIterable, Sendable {
    /// OpenAI (GPT 系列)
    case openAI
    /// Anthropic (Claude 系列)
    case anthropic
    /// 本地模型
    case local
    /// 自定义提供者
    case custom
    /// Apple Intelligence (FoundationModels)
    case appleIntelligence
}

/// LLM 提供者配置
public struct LLMProviderConfig: Sendable, Equatable {
    /// 提供者类型
    public let providerType: LLMProviderType
    /// API Key
    public let apiKey: String?
    /// 基础 URL（用于自定义端点）
    public let baseURL: URL?
    /// 模型标识符
    public let modelIdentifier: String
    /// 附加选项
    public let options: [String: String]

    public init(
        providerType: LLMProviderType,
        apiKey: String? = nil,
        baseURL: URL? = nil,
        modelIdentifier: String,
        options: [String: String] = [:]
    ) {
        self.providerType = providerType
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelIdentifier = modelIdentifier
        self.options = options
    }
}

/// LLM 提供者协议
///
/// 定义与具体 LLM 服务交互的接口。
public protocol LLMProvider: AnyObject, Sendable {

    /// 提供者类型
    var providerType: LLMProviderType { get }

    /// 是否可用
    var isAvailable: Bool { get }

    /// 当前配置
    var config: LLMProviderConfig { get }

    // MARK: - 通用文本完成

    /// 通用文本完成
    ///
    /// 使用 LLM 生成文本响应，适用于任何需要文本生成的场景。
    ///
    /// - Parameter prompt: 输入提示词
    /// - Returns: LLM 生成的响应文本
    /// - Throws: `VoxError.llmRequestFailed` 如果请求失败
    func complete(prompt: String) async throws -> String

    /// 流式文本完成
    ///
    /// 使用流式输出的方式生成文本响应。
    ///
    /// - Parameter prompt: 输入提示词
    /// - Returns: 异步文本流
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error>

    // MARK: - 内容分析

    /// 执行内容分析（意图、语气、实体、标签、参数）
    ///
    /// - Parameters:
    ///   - request: 分析请求
    ///   - steps: 需要分析的步骤集合
    /// - Returns: 可能只包含部分步骤的分析结果
    func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis

    // MARK: - 文本优化（便捷方法）

    /// 执行文本优化
    ///
    /// 针对文本优化场景的便捷方法，内部调用 complete 并封装结果。
    ///
    /// - Parameter request: 优化请求
    /// - Returns: 优化响应
    /// - Throws: `VoxError.llmRequestFailed` 如果请求失败
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse

    /// 流式文本优化
    ///
    /// - Parameter request: 优化请求
    /// - Returns: 异步文本流
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error>

    /// 验证配置有效性
    ///
    /// - Throws: 配置无效时抛出错误
    func validate() async throws

    /// 取消当前请求
    func cancel()
}
