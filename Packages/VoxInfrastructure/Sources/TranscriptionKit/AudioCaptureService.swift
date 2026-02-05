import Foundation
import Combine

/// 音频捕获状态
public enum AudioCaptureState: Sendable, Equatable {
    /// 空闲状态
    case idle
    /// 正在录音
    case recording
    /// 已暂停
    case paused
    /// 发生错误
    case error(String)
}

/// 音频捕获服务协议
///
/// 负责从麦克风捕获音频数据，供语音识别服务使用。
public protocol AudioCaptureService: AnyObject, Sendable {

    /// 当前捕获状态
    var state: AudioCaptureState { get }

    /// 状态变更发布者
    var statePublisher: AnyPublisher<AudioCaptureState, Never> { get }

    /// 音频电平发布者（0.0 - 1.0）
    ///
    /// 用于显示录音时的音量指示器。
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }

    /// 开始捕获音频
    ///
    /// - Throws: `VoxError.microphoneAccessDenied` 如果没有麦克风权限
    func startCapture() async throws

    /// 停止捕获音频
    func stopCapture() async

    /// 暂停捕获
    func pauseCapture()

    /// 恢复捕获
    func resumeCapture()

    /// 请求麦克风权限
    ///
    /// - Returns: 是否获得权限
    func requestPermission() async -> Bool

    /// 检查麦克风权限状态
    var hasPermission: Bool { get }
}
