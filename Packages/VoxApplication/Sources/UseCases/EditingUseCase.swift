import Foundation
import Combine
import CoreModels

/// 编辑用例协议
///
/// 负责处理用户的文本编辑操作，并将其转换为可撤销的补丁。
public protocol EditingUseCase: AnyObject, Sendable {

    /// 当前文本内容
    var currentText: String { get }

    /// 当前文本发布者
    var currentTextPublisher: AnyPublisher<String, Never> { get }

    /// 应用用户编辑
    ///
    /// 将用户在编辑器中的修改转换为补丁并提交到历史。
    ///
    /// - Parameters:
    ///   - range: 被修改的范围
    ///   - newText: 新文本
    /// - Throws: 编辑无效时抛出错误
    func applyEdit(range: CoreModels.TextRange, newText: String) throws

    /// 替换全部文本
    ///
    /// - Parameter text: 新的完整文本
    /// - Throws: 替换失败时抛出错误
    func replaceAll(with text: String) throws

    /// 在指定位置插入文本
    ///
    /// - Parameters:
    ///   - text: 要插入的文本
    ///   - location: 插入位置
    /// - Throws: 插入失败时抛出错误
    func insert(_ text: String, at location: Int) throws

    /// 删除指定范围的文本
    ///
    /// - Parameter range: 要删除的范围
    /// - Throws: 删除失败时抛出错误
    func delete(range: CoreModels.TextRange) throws

    /// 追加文本到末尾
    ///
    /// - Parameter text: 要追加的文本
    /// - Throws: 追加失败时抛出错误
    func append(_ text: String) throws

    /// 合并最近的编辑
    ///
    /// 将最近的连续用户编辑合并为单个补丁，优化撤销粒度。
    func mergeRecentEdits()

    // MARK: - Voice Zone

    /// 语音锚点位置（nil 表示未设置）
    var voiceAnchorLocation: Int? { get }

    /// 语音区域是否已锁定（锁定时不允许外部修改语音区域）
    var isVoiceZoneLocked: Bool { get }

    /// 设置语音锚点
    /// - Parameter location: 锚点字符索引（语音区域从此位置开始，到文本末尾）
    func setVoiceAnchor(_ location: Int)

    /// 清除语音锚点
    func clearVoiceAnchor()

    /// 设置语音区域锁定状态
    /// - Parameter locked: true 表示锁定，false 表示解锁
    func setVoiceZoneLocked(_ locked: Bool)

    /// 替换语音区域文本（绕过锁定检查，由 StreamingInputCoordinator 专用）
    ///
    /// - Parameter text: 替换语音区域的新文本
    /// - Throws: 锚点未设置时抛出错误
    func replaceVoiceZone(with text: String) throws
}
