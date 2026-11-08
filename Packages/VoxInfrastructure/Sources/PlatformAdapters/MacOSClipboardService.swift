#if os(macOS)
import Foundation
import AppKit
import ApplicationServices
import Carbon
import LokiKit

/// macOS 剪贴板服务实现
///
/// 使用 NSPasteboard 进行剪贴板操作，
/// 使用 CGEvent 模拟粘贴快捷键。
public final class MacOSClipboardService: ClipboardService, @unchecked Sendable {

    // MARK: - 单例

    public static let shared = MacOSClipboardService()

    // MARK: - 属性

    private let pasteboard = NSPasteboard.general
    private let logger: Logger = PrintLogger(subsystem: "Clipboard")

    // MARK: - 初始化

    private init() {}

    // MARK: - ClipboardService 协议实现

    public func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.log(.debug, "Copied text to pasteboard", context: ["char_count": text.count])
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
        logger.debug("Simulating paste keyboard shortcut")

        let env = ProcessInfo.processInfo.environment
        let isRunningTests = env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
        if !isRunningTests && !AXIsProcessTrusted() {
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey: kCFBooleanTrue!] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // 若用户刚松开 Space 但手指尚未完全离开 Option/Shift/Control，在发出任何按键前异步等待物理修饰键释放，避免合成出 Cmd+Option+V
        let conflictingModifiers: CGEventFlags = [.maskAlternate, .maskShift, .maskControl]
        for _ in 0..<20 {
            guard !Task.isCancelled else { return }
            if CGEventSource.flagsState(.hidSystemState).intersection(conflictingModifiers).isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard !Task.isCancelled else { return }

        // 使用 .privateState 隔离物理按键状态（避免刚松开 ⌥Space 时的 Option 修饰位混入 Cmd+V）
        let source = CGEventSource(stateID: .privateState)

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
        cmdUp.flags = []

        // 同步发送全部事件——HID 事件队列按顺序处理，无需延迟。
        // 不可在此使用 Task.sleep：若外层 Task 被取消（如窗口关闭），
        // sleep 会抛出 CancellationError，导致 cmdDown 已发出但 cmdUp 未发出，
        // 造成 Command 键卡住，后续所有按键都触发快捷键。
        let tapLocation = CGEventTapLocation.cghidEventTap
        cmdDown.post(tap: tapLocation)
        vDown.post(tap: tapLocation)
        vUp.post(tap: tapLocation)
        cmdUp.post(tap: tapLocation)

        logger.debug("Paste simulation complete")
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
