import Foundation

/// 文本注入用例协议 (macOS)
///
/// 负责将文本注入到其他应用的输入框中。
public protocol TextInjectionUseCase: AnyObject, Sendable {

    /// 将当前文本注入到聚焦的输入框
    ///
    /// 使用辅助功能 API 或剪贴板方式注入文本。
    ///
    /// - Throws: 权限不足或无聚焦输入框错误
    func injectToFocusedField() async throws

    /// 将指定文本注入到聚焦的输入框
    ///
    /// - Parameter text: 要注入的文本
    /// - Throws: 权限不足或无聚焦输入框错误
    func injectText(_ text: String) async throws

    /// 复制当前文本到剪贴板
    func copyToClipboard()

    /// 复制指定文本到剪贴板
    ///
    /// - Parameter text: 要复制的文本
    func copyToClipboard(_ text: String)

    /// 复制并模拟粘贴
    ///
    /// 将文本复制到剪贴板，然后模拟 Cmd+V 粘贴操作。
    func copyAndPaste() async throws

    /// 检查是否可以使用辅助功能注入
    var canUseAccessibility: Bool { get }

    /// 首选注入方式
    var preferredInjectionMethod: InjectionMethod { get set }
}

/// 文本注入方式
public enum InjectionMethod: String, Codable, Sendable {
    /// 使用剪贴板 + 模拟粘贴
    case clipboard
    /// 使用辅助功能 API 直接插入
    case accessibility
}
