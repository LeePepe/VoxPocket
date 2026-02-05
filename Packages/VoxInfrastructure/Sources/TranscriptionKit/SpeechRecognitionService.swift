import Foundation
import Combine

/// ASR（自动语音识别）提供者类型
public enum ASRProviderType: String, CaseIterable, Sendable {
    /// Apple Speech Framework
    case apple
    /// OpenAI Whisper
    case whisper
    /// 自定义提供者
    case custom
}

/// 语音识别服务协议
///
/// 负责将音频流转换为文本。
public protocol SpeechRecognitionService: AnyObject, Sendable {

    /// 提供者类型
    var providerType: ASRProviderType { get }

    /// 转录结果发布者
    ///
    /// 发布实时的转录结果，包括临时结果和最终结果。
    var resultPublisher: AnyPublisher<TranscriptionResult, Error> { get }

    /// 开始语音识别
    ///
    /// - Parameter language: 识别语言
    /// - Throws: `VoxError.speechRecognitionUnavailable` 如果服务不可用
    func startRecognition(language: Locale) async throws

    /// 停止语音识别
    func stopRecognition() async

    /// 检查服务可用性
    ///
    /// - Returns: 服务是否可用
    func checkAvailability() async -> Bool

    /// 请求语音识别权限
    ///
    /// - Returns: 是否获得权限
    func requestPermission() async -> Bool

    /// 获取支持的语言列表
    var supportedLanguages: [Locale] { get }
}
