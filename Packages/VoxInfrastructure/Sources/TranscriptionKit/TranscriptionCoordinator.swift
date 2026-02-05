import Foundation
import Combine

/// 转录协调器协议
///
/// 组合音频捕获服务和语音识别服务，提供统一的转录接口。
public protocol TranscriptionCoordinator: AnyObject, Sendable {

    /// 音频捕获服务
    var audioCaptureService: AudioCaptureService { get }

    /// 语音识别服务
    var speechRecognitionService: SpeechRecognitionService { get }

    /// 最终转录结果发布者（已过滤 partial 结果）
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { get }

    /// 实时转录发布者（包含 partial 结果）
    var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> { get }

    /// 当前音频电平
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }

    /// 是否正在转录
    var isTranscribing: Bool { get }

    /// 开始转录
    ///
    /// - Parameter language: 识别语言
    /// - Throws: 权限或服务不可用错误
    func start(language: Locale) async throws

    /// 停止转录
    func stop() async

    /// 暂停转录
    func pause()

    /// 恢复转录
    func resume()
}
