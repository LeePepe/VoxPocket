import Foundation

/// 转录生命周期事件
///
/// 用于向上层暴露 provider 对“语音开始 / 静音 / 音频结束 / 识别完成”的统一语义。
public enum TranscriptionLifecycleEvent: Sendable, Equatable {
    /// 已检测到有效语音内容
    case speechDetected
    /// 已检测到静音段
    case silenceDetected
    /// 音频输入已结束
    case audioEnded
    /// 本轮识别已完成，不会再有新的结果
    case recognitionCompleted
}
