import Foundation
import CoreModels

/// 补丁操作协议
///
/// 提供补丁的应用、反转和合并操作。
public protocol PatchOperating: Sendable {

    /// 将补丁应用到文本
    ///
    /// - Parameters:
    ///   - patch: 要应用的补丁
    ///   - text: 目标文本
    /// - Returns: 应用补丁后的新文本
    /// - Throws: `VoxError.patchApplicationFailed` 如果补丁与文本不匹配
    func apply(_ patch: Patch, to text: String) throws -> String

    /// 反转补丁（用于撤销操作）
    ///
    /// 生成一个与原补丁效果相反的补丁。
    ///
    /// - Parameter patch: 要反转的补丁
    /// - Returns: 反转后的补丁
    func invert(_ patch: Patch) -> Patch

    /// 合并连续的同源补丁
    ///
    /// 将多个连续的、来源相同的补丁合并为更少的补丁，
    /// 以优化历史存储和撤销粒度。
    ///
    /// - Parameter patches: 要合并的补丁数组
    /// - Returns: 合并后的补丁数组
    func merge(_ patches: [Patch]) -> [Patch]

    /// 验证补丁是否可以应用到指定文本
    ///
    /// - Parameters:
    ///   - patch: 要验证的补丁
    ///   - text: 目标文本
    /// - Returns: 如果补丁可以应用则返回 true
    func canApply(_ patch: Patch, to text: String) -> Bool
}
