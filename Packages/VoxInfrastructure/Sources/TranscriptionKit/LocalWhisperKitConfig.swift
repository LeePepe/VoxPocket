import Foundation

/// 本地 WhisperKit 转录配置
public struct LocalWhisperKitConfig: Sendable {
    /// WhisperKit 模型名，默认使用 turbo 版本
    public let model: String
    /// 首次开始时是否预热模型
    public let preloadOnStart: Bool

    public init(
        model: String = "openai_whisper-base",
        preloadOnStart: Bool = true
    ) {
        self.model = model
        self.preloadOnStart = preloadOnStart
    }

    public static let `default` = LocalWhisperKitConfig()

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
