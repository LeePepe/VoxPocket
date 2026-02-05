import Foundation

/// 剪贴板服务协议
///
/// 提供跨平台的剪贴板操作接口。
public protocol ClipboardService: AnyObject, Sendable {

    /// 复制文本到剪贴板
    ///
    /// - Parameter text: 要复制的文本
    func copy(_ text: String)

    /// 从剪贴板读取文本
    ///
    /// - Returns: 剪贴板中的文本，如果没有文本则返回 nil
    func paste() -> String?

    /// 清空剪贴板
    func clear()

    /// 模拟粘贴操作
    ///
    /// 将当前剪贴板内容粘贴到聚焦的输入框。
    ///
    /// - Throws: `VoxError.textInjectionFailed` 如果操作失败
    func simulatePaste() async throws

    /// 剪贴板是否包含文本
    var hasText: Bool { get }
}
