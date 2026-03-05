import Foundation

/// 用户意图类型
///
/// 通过分析语音转录文本，识别用户的真实意图，包括内容操作和自我纠正。
public enum UserIntent: Equatable, Sendable {
    /// 内容操作：需要对内容进行处理（翻译、润色等）
    case contentOperation(RefinementType, targetLanguage: String? = nil)

    /// 自我纠正：将口语化内容转为准确的文字表达，由 LLM 自行分析给出结果
    case selfCorrection

    /// 意图的显示名称
    public var displayName: String {
        switch self {
        case .contentOperation(let type, _):
            return type.displayName
        case .selfCorrection:
            return "自我纠正"
        }
    }

    /// 意图的描述
    public var description: String {
        switch self {
        case .contentOperation(let type, let targetLanguage):
            if let lang = targetLanguage {
                return "\(type.description) (目标语言: \(lang))"
            }
            return type.description
        case .selfCorrection:
            return "将口语化内容转为准确的文字表达"
        }
    }
}

/// 意图识别结果
///
/// 包含识别出的意图和置信度
public struct IntentRecognitionResult: Equatable, Sendable {
    /// 识别出的意图
    public let intent: UserIntent

    /// 置信度 (0.0 - 1.0)
    public let confidence: Double

    /// 是否高置信度（>= 0.7）
    public var isHighConfidence: Bool {
        confidence >= 0.7
    }

    public init(intent: UserIntent, confidence: Double) {
        self.intent = intent
        self.confidence = min(max(confidence, 0.0), 1.0)
    }
}
