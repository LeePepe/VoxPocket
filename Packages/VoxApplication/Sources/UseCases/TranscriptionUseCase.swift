import Foundation
import Combine
import TranscriptionKit

/// 转录用例协议
///
/// 负责管理语音转录流程，包括实时显示和结果提交。
public protocol TranscriptionUseCase: AnyObject, Sendable {

    /// 实时转录文本（包含临时结果）
    ///
    /// 显示用户当前正在说的内容，可能随时变化。
    var liveTextPublisher: AnyPublisher<String, Never> { get }

    /// 最终转录结果发布者
    ///
    /// 只发布稳定的最终结果。
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { get }

    /// 当前转录语言
    var currentLanguage: Locale { get }

    /// 设置转录语言
    ///
    /// - Parameter locale: 语言区域
    func setLanguage(_ locale: Locale)

    /// 获取支持的语言列表
    var supportedLanguages: [Locale] { get }

    /// 提交当前转录结果到历史
    ///
    /// 将最新的转录结果作为补丁提交到文本历史。
    func commitCurrentTranscription() async throws

    /// 清除临时转录内容
    func clearLiveText()

    // MARK: - Streaming Snapshot Gate

    /// 全量快照发布者
    ///
    /// 当 `snapshotGateActive` 为 true 时，每次最终识别结果到来时发布完整转录文本。
    /// 用于流式输入模式下的增量精炼。
    var snapshotPublisher: AnyPublisher<String, Never> { get }

    /// 快照门控开关
    ///
    /// true：最终识别结果路由到 snapshotPublisher，不写入 EditingUseCase
    /// false：最终识别结果通过 replaceAll 写入 EditingUseCase（默认行为）
    var snapshotGateActive: Bool { get set }
}
