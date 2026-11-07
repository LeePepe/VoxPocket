import Foundation
import CoreModels

/// Deep Link 动作
///
/// 定义 app 支持的 deep link 操作类型。
/// Widget、Control Center 控件、Shortcuts 等入口统一通过此枚举触发操作。
public enum DeepLinkAction: Sendable, Equatable {
    /// 开始录音
    case startRecording
    /// 在指定模式下开始录音
    case startRecordingInMode(CaptureMode)
    /// 停止录音
    case stopRecording
    /// 新建会话
    case newSession
    /// 打开指定会话
    case openSession(UUID)
}
