import Foundation

/// VoxPocket 领域错误
public enum VoxError: Error, LocalizedError, Sendable {

    // MARK: - 历史相关错误

    /// 无法撤销（已到达历史起点）
    case cannotUndo
    /// 无法重做（已到达历史末端）
    case cannotRedo
    /// 补丁应用失败
    case patchApplicationFailed(reason: String)
    /// 检查点数据损坏
    case checkpointCorrupted
    /// 历史状态不一致
    case historyInconsistent(reason: String)

    // MARK: - 转录相关错误

    /// 麦克风访问被拒绝
    case microphoneAccessDenied
    /// 语音识别不可用
    case speechRecognitionUnavailable
    /// 语音识别权限被拒绝
    case speechRecognitionPermissionDenied
    /// 转录失败
    case transcriptionFailed(reason: String)
    /// 不支持的语言
    case unsupportedLanguage(locale: String)

    // MARK: - LLM 相关错误

    /// LLM 提供者未配置
    case llmProviderNotConfigured
    /// LLM 请求失败
    case llmRequestFailed(reason: String)
    /// LLM 响应无效
    case llmResponseInvalid
    /// LLM API Key 无效
    case llmInvalidAPIKey
    /// LLM 配额已用尽
    case llmQuotaExceeded
    /// LLM 操作超时
    case llmOperationTimeout

    // MARK: - 持久化相关错误

    /// 会话未找到
    case sessionNotFound(id: UUID)
    /// 持久化操作失败
    case persistenceFailed(reason: String)
    /// 数据迁移失败
    case migrationFailed(reason: String)

    // MARK: - 模型加载相关错误

    /// 本地模型尚未就绪（仍在下载或初始化中）
    case modelNotReady

    // MARK: - 平台相关错误 (macOS)

    /// 辅助功能权限被拒绝
    case accessibilityPermissionDenied
    /// 文本注入失败
    case textInjectionFailed(reason: String)
    /// 无聚焦的输入框
    case noFocusedTextField

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .cannotUndo:
            return "无法撤销，已到达历史起点"
        case .cannotRedo:
            return "无法重做，已到达历史末端"
        case .patchApplicationFailed(let reason):
            return "补丁应用失败：\(reason)"
        case .checkpointCorrupted:
            return "检查点数据已损坏"
        case .historyInconsistent(let reason):
            return "历史状态不一致：\(reason)"
        case .microphoneAccessDenied:
            return "麦克风访问被拒绝，请在系统设置中允许访问"
        case .speechRecognitionUnavailable:
            return "语音识别服务不可用"
        case .speechRecognitionPermissionDenied:
            return "语音识别权限被拒绝，请在系统设置中允许"
        case .transcriptionFailed(let reason):
            return "转录失败：\(reason)"
        case .unsupportedLanguage(let locale):
            return "不支持的语言：\(locale)"
        case .llmProviderNotConfigured:
            return "LLM 提供者未配置"
        case .llmRequestFailed(let reason):
            return "LLM 请求失败：\(reason)"
        case .llmResponseInvalid:
            return "LLM 响应无效"
        case .llmInvalidAPIKey:
            return "无效的 API Key"
        case .llmQuotaExceeded:
            return "API 配额已用尽"
        case .llmOperationTimeout:
            return "LLM 操作超时"
        case .sessionNotFound(let id):
            return "会话未找到：\(id)"
        case .persistenceFailed(let reason):
            return "数据存储失败：\(reason)"
        case .migrationFailed(let reason):
            return "数据迁移失败：\(reason)"
        case .accessibilityPermissionDenied:
            return "辅助功能权限被拒绝，请在系统设置中允许"
        case .textInjectionFailed(let reason):
            return "文本注入失败：\(reason)"
        case .noFocusedTextField:
            return "没有聚焦的输入框"
        case .modelNotReady:
            return "本地模型正在加载中，请稍候再试"
        }
    }
}
