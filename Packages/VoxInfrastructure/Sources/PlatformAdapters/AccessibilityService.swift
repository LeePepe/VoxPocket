import Foundation

/// 辅助功能权限状态
public enum AccessibilityPermissionStatus: Sendable {
    /// 已授权
    case authorized
    /// 已拒绝
    case denied
    /// 未确定
    case notDetermined
}

/// 辅助功能服务协议 (macOS)
///
/// 提供通过辅助功能 API 操作其他应用的接口。
/// 需要用户在系统设置中明确授权。
public protocol AccessibilityService: AnyObject, Sendable {

    /// 当前权限状态
    var permissionStatus: AccessibilityPermissionStatus { get }

    /// 请求辅助功能权限
    ///
    /// 会打开系统偏好设置让用户授权。
    ///
    /// - Returns: 是否已获得权限
    func requestPermission() async -> Bool

    /// 检查权限状态
    ///
    /// - Returns: 是否已授权
    func checkPermission() -> Bool

    /// 向当前聚焦的输入框插入文本
    ///
    /// - Parameter text: 要插入的文本
    /// - Throws: `VoxError.accessibilityPermissionDenied` 或 `VoxError.noFocusedTextField`
    func insertTextToFocusedElement(_ text: String) async throws

    /// 获取当前聚焦元素的文本
    ///
    /// - Returns: 聚焦元素中的文本
    /// - Throws: `VoxError.accessibilityPermissionDenied` 或 `VoxError.noFocusedTextField`
    func getTextFromFocusedElement() async throws -> String?

    /// 获取当前聚焦元素的选中文本
    ///
    /// - Returns: 选中的文本
    /// - Throws: 权限或无聚焦元素错误
    func getSelectedTextFromFocusedElement() async throws -> String?

    /// 替换当前聚焦元素的选中文本
    ///
    /// - Parameter text: 替换文本
    /// - Throws: 权限或无聚焦元素错误
    func replaceSelectedTextInFocusedElement(_ text: String) async throws
}
