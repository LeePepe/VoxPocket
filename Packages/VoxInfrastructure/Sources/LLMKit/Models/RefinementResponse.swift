import Foundation

/// LLM 优化响应
public struct RefinementResponse: Sendable, Equatable {
    /// 原始文本
    public let originalText: String
    /// 优化后的文本
    public let refinedText: String
    /// 意图分析
    public let intentAnalysis: IntentAnalysis
    /// 语气分析
    public let toneAnalysis: ToneAnalysis
    /// 缺失的分析步骤
    public let missingAnalysisSteps: Set<AnalysisStep>
    /// 完成时间戳
    public let timestamp: Date
    /// 使用的 token 数量（如果可用）
    public let tokenUsage: TokenUsage?

    public init(
        originalText: String,
        refinedText: String,
        intentAnalysis: IntentAnalysis = IntentAnalysis(),
        toneAnalysis: ToneAnalysis = ToneAnalysis(),
        missingAnalysisSteps: Set<AnalysisStep> = [],
        timestamp: Date = Date(),
        tokenUsage: TokenUsage? = nil
    ) {
        self.originalText = originalText
        self.refinedText = refinedText
        self.intentAnalysis = intentAnalysis
        self.toneAnalysis = toneAnalysis
        self.missingAnalysisSteps = missingAnalysisSteps
        self.timestamp = timestamp
        self.tokenUsage = tokenUsage
    }
}

/// Token 使用统计
public struct TokenUsage: Sendable, Equatable, Codable {
    /// 输入 token 数
    public let promptTokens: Int
    /// 输出 token 数
    public let completionTokens: Int
    /// 总 token 数
    public var totalTokens: Int {
        promptTokens + completionTokens
    }

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}
