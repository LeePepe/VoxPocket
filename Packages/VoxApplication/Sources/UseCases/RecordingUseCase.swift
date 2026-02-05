import Foundation
import Combine

/// 录音状态
public enum RecordingState: Equatable, Sendable {
    /// 空闲
    case idle
    /// 录音中
    case recording(duration: TimeInterval)
    /// 已暂停
    case paused(duration: TimeInterval)
    /// 处理中（停止录音后的转录阶段）
    case processing
    /// 发生错误
    case error(String)

    /// 是否正在录音或暂停
    public var isActive: Bool {
        switch self {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }

    /// 当前录音时长
    public var duration: TimeInterval? {
        switch self {
        case .recording(let d), .paused(let d):
            return d
        default:
            return nil
        }
    }
}

/// 录音用例协议
///
/// 负责录音的启动、停止、暂停等操作。
public protocol RecordingUseCase: AnyObject, Sendable {

    /// 当前录音状态
    var state: RecordingState { get }

    /// 状态变更发布者
    var statePublisher: AnyPublisher<RecordingState, Never> { get }

    /// 音频电平发布者（0.0 - 1.0）
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }

    /// 开始录音
    ///
    /// - Throws: 权限不足或设备不可用错误
    func startRecording() async throws

    /// 停止录音
    ///
    /// 停止录音并等待最终转录结果。
    func stopRecording() async throws

    /// 暂停录音
    func pauseRecording()

    /// 恢复录音
    func resumeRecording()

    /// 取消录音
    ///
    /// 取消当前录音，不保存任何内容。
    func cancelRecording()

    /// 检查录音权限
    ///
    /// - Returns: 是否有录音权限
    func checkPermission() async -> Bool

    /// 请求录音权限
    ///
    /// - Returns: 是否获得权限
    func requestPermission() async -> Bool
}
