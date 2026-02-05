import Foundation

/// 会话状态
public enum SessionState: String, Codable, Equatable, Sendable {
    /// 空闲状态
    case idle
    /// 正在录音
    case recording
    /// 正在转录
    case transcribing
    /// 正在 LLM 优化
    case refining
}
