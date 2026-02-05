import Foundation

/// LLM 优化操作类型
public enum RefinementType: String, CaseIterable, Codable, Sendable {
    /// 重写（保持原意，改变表达方式）
    case rewrite
    /// 润色（改善语法和流畅度）
    case polish
    /// 摘要（提取核心要点）
    case summarize
    /// 扩展（增加细节和内容）
    case expand
    /// 纠错（修正拼写和语法错误）
    case correct
    /// 翻译
    case translate
    /// 自定义（使用用户提供的提示词）
    case custom

    /// 显示名称
    public var displayName: String {
        switch self {
        case .rewrite: return "重写"
        case .polish: return "润色"
        case .summarize: return "摘要"
        case .expand: return "扩展"
        case .correct: return "纠错"
        case .translate: return "翻译"
        case .custom: return "自定义"
        }
    }

    /// 描述
    public var description: String {
        switch self {
        case .rewrite: return "保持原意，改变表达方式"
        case .polish: return "改善语法和流畅度"
        case .summarize: return "提取核心要点"
        case .expand: return "增加细节和内容"
        case .correct: return "修正拼写和语法错误"
        case .translate: return "翻译为其他语言"
        case .custom: return "使用自定义提示词"
        }
    }

    /// 根据优化类型构建完整的提示词
    ///
    /// - Parameters:
    ///   - text: 要优化的原始文本
    ///   - customPrompt: 自定义提示词（仅当 type 为 .custom 时使用）
    ///   - targetLanguage: 目标语言（仅当 type 为 .translate 时使用）
    /// - Returns: 完整的提示词字符串
    public func buildPrompt(for text: String, customPrompt: String? = nil, targetLanguage: Locale? = nil) -> String {
        let instruction: String
        switch self {
        case .polish:
            instruction = "请润色以下语音转录文本，改善语法和流畅度，保持原意不变。只输出润色后的文本，不要添加任何解释。"
        case .rewrite:
            instruction = "请重写以下文本，保持原意但改变表达方式。只输出重写后的文本，不要添加任何解释。"
        case .summarize:
            instruction = "请提取以下文本的核心要点，生成简洁的摘要。只输出摘要内容，不要添加任何解释。"
        case .expand:
            instruction = "请扩展以下文本，增加细节和相关内容。只输出扩展后的文本，不要添加任何解释。"
        case .correct:
            instruction = "请修正以下文本中的拼写和语法错误。只输出修正后的文本，不要添加任何解释。"
        case .translate:
            let lang = targetLanguage?.identifier ?? "en"
            instruction = "请将以下文本翻译为 \(lang)。只输出翻译结果，不要添加任何解释。"
        case .custom:
            instruction = customPrompt ?? "请改善以下文本。只输出改善后的文本，不要添加任何解释。"
        }
        return "\(instruction)\n\n\(text)"
    }
}
