import Foundation

/// 文本变更的来源
public enum ChangeSource: String, Codable, Equatable, Sendable {
    /// 语音转录生成
    case voice
    /// 语音纠错/改写指令
    case voiceCorrection
    /// LLM 优化生成
    case llmRefinement
}

extension ChangeSource {
    public init(from decoder: Decoder) throws {
        let rawValue = try String(from: decoder)
        switch rawValue {
        case ChangeSource.voice.rawValue:
            self = .voice
        case ChangeSource.llmRefinement.rawValue:
            self = .llmRefinement
        case ChangeSource.voiceCorrection.rawValue:
            self = .voiceCorrection
        case "userEdit":
            // Legacy persisted value; map to voice correction.
            self = .voiceCorrection
        default:
            // Be resilient to unknown future values.
            self = .voice
        }
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}
