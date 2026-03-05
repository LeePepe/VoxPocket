import Foundation
import FoundationModels

/// 快速意图分析（简化版，用于提高性能）
///
/// 只包含核心字段，避免复杂的 guided generation
@Generable
public struct FastIntentAnalysis: Sendable, Equatable {
    @Guide(description: "意图类型：self_correction / translate / polish / correct / summarize / expand")
    public let intent: IntentKind
    @Guide(description: "置信度 0.0-1.0")
    public let confidence: Double

    public init(intent: IntentKind = .selfCorrection, confidence: Double = 0.0) {
        self.intent = intent
        self.confidence = min(max(confidence, 0.0), 1.0)
    }
}
