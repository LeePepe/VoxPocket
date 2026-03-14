import Foundation

/// 本地 WhisperKit 转录配置
public struct LocalWhisperKitConfig: Sendable {
    /// WhisperKit 模型名（iOS 默认 base，macOS 默认 large-v3-turbo）
    public let model: String
    /// 首次开始时是否预热模型
    public let preloadOnStart: Bool

    public static var platformDefaultModel: String {
#if os(iOS)
        return "openai/whisper-base"
#else
        return "openai/whisper-large-v3-turbo"
#endif
    }

    public init(
        model: String = LocalWhisperKitConfig.platformDefaultModel,
        preloadOnStart: Bool = true
    ) {
        self.model = model
        self.preloadOnStart = preloadOnStart
    }

    public static let `default` = LocalWhisperKitConfig()
    public static let failingForTest = LocalWhisperKitConfig(
        model: "__failing_model_for_test__",
        preloadOnStart: true
    )

    /// WhisperKit 真实可下载的 variant 名称（兼容常见别名）
    public var resolvedModelVariant: String {
        switch model {
        case "openai/whisper-base":
            return "openai_whisper-base"
        case "openai/whisper-large-v3":
            return "openai_whisper-large-v3"
        case "openai/whisper-large-v3-turbo":
            return "openai_whisper-large-v3_turbo"
        case "distil-whisper/distil-large-v3":
            return "distil-whisper_distil-large-v3"
        case "distil-whisper/distil-large-v3-turbo":
            return "distil-whisper_distil-large-v3_turbo"
        default:
            return model
        }
    }

    /// 根据 locale 生成 Whisper 语言 hint（BCP-47 -> ISO-639 简码）
    public func languageHint(for locale: Locale) -> String? {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("zh") {
            return "zh"
        }
        if identifier.hasPrefix("en") {
            return "en"
        }
        return locale.language.languageCode?.identifier
    }
}
