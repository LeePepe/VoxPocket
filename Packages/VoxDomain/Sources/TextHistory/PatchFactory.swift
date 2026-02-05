import Foundation
import CoreModels

/// 补丁创建工厂协议
///
/// 提供创建各种类型补丁的便捷方法。
public protocol PatchFactory: Sendable {

    /// 从文本差异创建补丁数组
    ///
    /// 比较新旧文本，自动生成最小化的补丁序列。
    ///
    /// - Parameters:
    ///   - oldText: 原始文本
    ///   - newText: 新文本
    ///   - source: 变更来源
    /// - Returns: 补丁数组
    func createPatches(
        oldText: String,
        newText: String,
        source: ChangeSource
    ) -> [Patch]

    /// 创建插入补丁
    ///
    /// - Parameters:
    ///   - location: 插入位置
    ///   - text: 要插入的文本
    ///   - source: 变更来源
    /// - Returns: 插入补丁
    func createInsertPatch(
        at location: Int,
        text: String,
        source: ChangeSource
    ) -> Patch

    /// 创建删除补丁
    ///
    /// - Parameters:
    ///   - range: 要删除的范围
    ///   - deletedText: 被删除的文本（用于撤销）
    ///   - source: 变更来源
    /// - Returns: 删除补丁
    func createDeletePatch(
        range: CoreModels.TextRange,
        deletedText: String,
        source: ChangeSource
    ) -> Patch

    /// 创建替换补丁
    ///
    /// - Parameters:
    ///   - range: 要替换的范围
    ///   - oldText: 被替换的原始文本
    ///   - newText: 替换后的新文本
    ///   - source: 变更来源
    /// - Returns: 替换补丁
    func createReplacePatch(
        range: CoreModels.TextRange,
        oldText: String,
        newText: String,
        source: ChangeSource
    ) -> Patch
}
