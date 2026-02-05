#if os(macOS)
import Foundation
import AppKit
import Carbon

/// macOS 剪贴板服务实现
///
/// 使用 NSPasteboard 进行剪贴板操作，
/// 使用 CGEvent 模拟粘贴快捷键。
public final class MacOSClipboardService: ClipboardService, @unchecked Sendable {

    // MARK: - 单例

    public static let shared = MacOSClipboardService()

    // MARK: - 属性

    private let pasteboard = NSPasteboard.general

    // MARK: - 初始化

    private init() {}

    // MARK: - ClipboardService 协议实现

    public func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 [Clipboard] Copied \(text.count) characters")
    }

    public func paste() -> String? {
        pasteboard.string(forType: .string)
    }

    public func clear() {
        pasteboard.clearContents()
    }

    public var hasText: Bool {
        pasteboard.string(forType: .string) != nil
    }

    public func simulatePaste() async throws {
        print("📋 [Clipboard] Simulating paste (Cmd+V)")

        // 创建 Cmd+V 按键事件序列
        let source = CGEventSource(stateID: .hidSystemState)

        // V 键的虚拟键码
        let vKeyCode: CGKeyCode = 9

        // Cmd 键按下
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true) else {
            throw ClipboardError.eventCreationFailed
        }
        cmdDown.flags = .maskCommand

        // V 键按下（带 Cmd 修饰键）
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            throw ClipboardError.eventCreationFailed
        }
        vDown.flags = .maskCommand

        // V 键释放
        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw ClipboardError.eventCreationFailed
        }
        vUp.flags = .maskCommand

        // Cmd 键释放
        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else {
            throw ClipboardError.eventCreationFailed
        }

        // 发送事件序列
        let tapLocation = CGEventTapLocation.cghidEventTap

        cmdDown.post(tap: tapLocation)
        try await Task.sleep(for: .milliseconds(10))

        vDown.post(tap: tapLocation)
        try await Task.sleep(for: .milliseconds(10))

        vUp.post(tap: tapLocation)
        try await Task.sleep(for: .milliseconds(10))

        cmdUp.post(tap: tapLocation)

        print("✅ [Clipboard] Paste simulation complete")
    }
}

// MARK: - 错误类型

public enum ClipboardError: LocalizedError {
    case eventCreationFailed
    case pasteSimulationFailed

    public var errorDescription: String? {
        switch self {
        case .eventCreationFailed:
            return "Failed to create keyboard event"
        case .pasteSimulationFailed:
            return "Failed to simulate paste operation"
        }
    }
}
#endif
