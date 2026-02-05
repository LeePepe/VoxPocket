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
}
