import Foundation

/// 用户意图类型
///
/// 通过分析语音转录文本，识别用户的真实意图，包括内容操作、自我纠正、删除等。
public enum UserIntent: Equatable, Sendable {
    /// 内容操作：需要对内容进行处理（翻译、润色等）
    case contentOperation(RefinementType, targetLanguage: String? = nil)

    /// 自我纠正：用户发现说错了，要修正
    /// - original: 原始错误内容
    /// - corrected: 修正后的内容
    case selfCorrection(original: String, corrected: String)

    /// 删除/撤销：用户否定之前说的内容
    case deletion

    /// 纯内容：没有特殊意图，就是普通转录
    case plainContent

    /// 意图的显示名称
    public var displayName: String {
        switch self {
        case .contentOperation(let type, _):
            return type.displayName
        case .selfCorrection:
            return "自我纠正"
        case .deletion:
            return "删除"
        case .plainContent:
            return "普通内容"
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
        case .selfCorrection(let original, let corrected):
            return "将 '\(original)' 修正为 '\(corrected)'"
        case .deletion:
            return "删除或撤销之前的内容"
        case .plainContent:
            return "普通内容，无特殊操作"
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
