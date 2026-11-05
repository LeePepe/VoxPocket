import Foundation

public enum VoxKitError: Error, LocalizedError, Sendable, Equatable {
    case microphoneAccessDenied
    case speechRecognitionUnavailable
    case speechRecognitionPermissionDenied
    case transcriptionFailed(reason: VoxLabel)
    case unsupportedLanguage(locale: VoxLabel)
    case llmProviderNotConfigured
    case llmRequestFailed(reason: VoxLabel)
    case llmResponseInvalid
    case llmInvalidAPIKey
    case llmQuotaExceeded
    case llmOperationTimeout
    case modelNotReady

    public var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied: return "麦克风访问被拒绝，请在系统设置中允许访问"
        case .speechRecognitionUnavailable: return "语音识别服务不可用"
        case .speechRecognitionPermissionDenied: return "语音识别权限被拒绝，请在系统设置中允许"
        case .transcriptionFailed(let reason): return "转录失败：\(reason.rawLabel)"
        case .unsupportedLanguage(let locale): return "不支持的语言：\(locale.rawLabel)"
        case .llmProviderNotConfigured: return "LLM 提供者未配置"
        case .llmRequestFailed(let reason): return "LLM 请求失败：\(reason.rawLabel)"
        case .llmResponseInvalid: return "LLM 响应无效"
        case .llmInvalidAPIKey: return "无效的 API Key"
        case .llmQuotaExceeded: return "API 配额已用尽"
        case .llmOperationTimeout: return "LLM 操作超时"
        case .modelNotReady: return "本地模型正在加载中，请稍候再试"
        }
    }
}
