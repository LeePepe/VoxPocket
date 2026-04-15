#if os(macOS)
import Foundation
import AppKit
import ApplicationServices
import LokiKit

/// macOS 辅助功能服务实现
///
/// 使用 AXUIElement API 操作其他应用的 UI 元素。
public final class MacOSAccessibilityService: AccessibilityService, @unchecked Sendable {

    // MARK: - 单例

    public static let shared = MacOSAccessibilityService()
    private let logger: Logger = PrintLogger(subsystem: "Accessibility")

    // MARK: - 初始化

    private init() {}

    // MARK: - AccessibilityService 协议实现

    public var permissionStatus: AccessibilityPermissionStatus {
        if AXIsProcessTrusted() {
            return .authorized
        } else {
            return .denied
        }
    }

    public func requestPermission() async -> Bool {
        // 创建选项字典，提示系统弹出权限请求对话框
        // 使用字符串常量绕过 Swift 6 并发检查
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: kCFBooleanTrue!] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        if !isTrusted {
            // 打开系统偏好设置的辅助功能页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        return isTrusted
    }

    public func checkPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public func insertTextToFocusedElement(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw AccessibilityError.permissionDenied
        }

        guard let focusedElement = try getFocusedTextElement() else {
            throw AccessibilityError.noFocusedTextField
        }

        // 获取当前值
        var currentValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &currentValue)

        let currentText = currentValue as? String ?? ""

        // 获取当前选择范围
        var selectedRangeValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)

        var insertionPoint = currentText.count

        if let rangeValue = selectedRangeValue {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                insertionPoint = range.location
            }
        }

        // 在插入点插入文本
        let newText: String
        if insertionPoint >= 0 && insertionPoint <= currentText.count {
            let index = currentText.index(currentText.startIndex, offsetBy: insertionPoint)
            var mutableText = currentText
            mutableText.insert(contentsOf: text, at: index)
            newText = mutableText
        } else {
            newText = currentText + text
        }

        // 设置新值
        let result = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, newText as CFTypeRef)

        guard result == .success else {
            throw AccessibilityError.operationFailed(status: result)
        }

        logger.log(.debug, "Inserted text into focused element", context: [
            "char_count": text.count
        ])
    }

    public func getTextFromFocusedElement() async throws -> String? {
        guard AXIsProcessTrusted() else {
            throw AccessibilityError.permissionDenied
        }

        guard let focusedElement = try getFocusedTextElement() else {
            throw AccessibilityError.noFocusedTextField
        }

        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &value)

        guard result == .success else {
            throw AccessibilityError.operationFailed(status: result)
        }

        return value as? String
    }

    public func getSelectedTextFromFocusedElement() async throws -> String? {
        guard AXIsProcessTrusted() else {
            throw AccessibilityError.permissionDenied
        }

        guard let focusedElement = try getFocusedTextElement() else {
            throw AccessibilityError.noFocusedTextField
        }

        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &value)

        guard result == .success else {
            return nil
        }

        return value as? String
    }

    public func replaceSelectedTextInFocusedElement(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw AccessibilityError.permissionDenied
        }

        guard let focusedElement = try getFocusedTextElement() else {
            throw AccessibilityError.noFocusedTextField
        }

        let result = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)

        guard result == .success else {
            throw AccessibilityError.operationFailed(status: result)
        }

        logger.log(.debug, "Replaced selected text in focused element", context: [
            "char_count": text.count
        ])
    }

    // MARK: - 私有方法

    /// 获取当前聚焦的文本元素
    private func getFocusedTextElement() throws -> AXUIElement? {
        // 获取系统焦点应用
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        var result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

        guard result == .success, let app = focusedApp else {
            return nil
        }

        // 获取应用的聚焦元素
        var focusedElement: AnyObject?
        result = AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement as! AXUIElement? else {
            return nil
        }

        // 验证元素是否支持文本输入
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        let textRoles: [String] = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField"  // kAXSearchFieldRole
        ]

        if let roleString = role as? String, textRoles.contains(roleString) {
            return element
        }

        // 检查是否有 AXValue 属性（可能是自定义文本输入控件）
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           value is String {
            return element
        }

        return nil
    }
}

// MARK: - 错误类型

public enum AccessibilityError: LocalizedError {
    case permissionDenied
    case noFocusedTextField
    case operationFailed(status: AXError)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission denied. Please enable in System Settings > Privacy & Security > Accessibility."
        case .noFocusedTextField:
            return "No text field is currently focused."
        case .operationFailed(let status):
            return "Accessibility operation failed with status: \(status.rawValue)"
        }
    }
}
#endif
