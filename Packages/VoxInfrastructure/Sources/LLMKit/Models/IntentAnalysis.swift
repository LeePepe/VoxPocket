import Foundation
import FoundationModels

@Generable
public enum IntentKind: String, Sendable, Equatable {
    case selfCorrection = "self_correction"
    case translate
    case polish
    case correct
    case summarize
    case expand
}

@Generable
public struct IntentParams: Sendable, Equatable {
    @Guide(description: "目标语言，例如 en 或 zh-Hans（可选）")
    public let targetLanguage: String?

    public init(
        targetLanguage: String? = nil
    ) {
        self.targetLanguage = targetLanguage
    }
}

@Generable
public struct IntentAnalysis: Sendable, Equatable {
    @Guide(description: "意图：self_correction / translate / polish / correct / summarize / expand")
    public let intent: IntentKind
    @Guide(description: "意图置信度，0.0 到 1.0")
    public let confidence: Double
    @Guide(description: "意图相关参数")
    public let params: IntentParams
    @Guide(description: "关键实体（人名、地点、日期、时间等）")
    public let entities: [String]
    @Guide(description: "主题或类别标签")
    public let tags: [String]

    public init(
        intent: IntentKind = .selfCorrection,
        confidence: Double = 0.0,
        params: IntentParams = IntentParams(),
        entities: [String] = [],
        tags: [String] = []
    ) {
        self.intent = intent
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.params = params
        self.entities = entities
        self.tags = tags
    }

    public var logDescription: String {
        var parts: [String] = ["意图:\(intent.rawValue)"]
        parts.append("置信度:\(String(format: "%.2f", confidence))")
        if !entities.isEmpty { parts.append("实体:\(entities.joined(separator: ","))") }
        if !tags.isEmpty { parts.append("标签:\(tags.joined(separator: ","))") }
        return parts.joined(separator: " | ")
    }
}
