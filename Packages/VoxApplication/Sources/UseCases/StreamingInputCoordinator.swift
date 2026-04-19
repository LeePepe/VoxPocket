import Foundation
import Combine

/// 流式输入协调器协议
///
/// 协调转录快照流与 LLM 增量精炼，将结果实时写入 EditingUseCase 的语音区域。
/// 支持长文本输入：transcriber 不断提交快照 → 每次触发精炼 → 结果写入语音区域。
public protocol StreamingInputCoordinator: AnyObject, Sendable {

    /// 已精炼的语音文本发布者（每次写入语音区域时发布）
    var refinedVoiceTextPublisher: AnyPublisher<String, Never> { get }

    /// 开始流式输入
    ///
    /// 设置语音锚点、激活快照门控、订阅快照流。
    func startStreaming() async

    /// 停止流式输入
    ///
    /// 关闭快照门控、等待最终精炼完成（最多 5 秒）、解锁语音区域。
    func stopStreaming() async

    /// 取消流式输入（不等待精炼完成）
    func cancel()
}
