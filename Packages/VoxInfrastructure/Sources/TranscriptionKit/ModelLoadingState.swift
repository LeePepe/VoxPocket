import Foundation

/// 本地模型的加载状态
public enum ModelLoadingState: Equatable, Sendable {
    /// 未使用本地模型，或尚未开始
    case idle
    /// 正在下载模型文件（0.0–1.0）
    case downloading(progress: Double)
    /// 文件就绪，正在初始化推理管线
    case loading
    /// 模型已就绪，可以开始录音
    case ready
    /// 加载失败
    case failed(String)

    public var isInProgress: Bool {
        switch self {
        case .downloading, .loading: return true
        default: return false
        }
    }
}
