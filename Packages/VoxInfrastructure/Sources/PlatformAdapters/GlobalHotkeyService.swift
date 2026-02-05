import Foundation
import Combine

/// 快捷键定义
public struct HotkeyDefinition: Codable, Equatable, Sendable, Hashable {
    /// 键码
    public let keyCode: UInt16
    /// 修饰键
    public let modifiers: UInt
    /// 标识符
    public let identifier: String

    public init(keyCode: UInt16, modifiers: UInt, identifier: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.identifier = identifier
    }

    /// 显示字符串（如 "⌘⇧R"）
    public var displayString: String {
        var parts: [String] = []

        // 修饰键
        if modifiers & (1 << 0) != 0 { parts.append("⌃") }  // Control
        if modifiers & (1 << 1) != 0 { parts.append("⌥") }  // Option
        if modifiers & (1 << 2) != 0 { parts.append("⇧") }  // Shift
        if modifiers & (1 << 3) != 0 { parts.append("⌘") }  // Command

        // TODO: 根据 keyCode 转换为可读字符
        parts.append("Key(\(keyCode))")

        return parts.joined()
    }
}

/// 预定义的快捷键标识符
public enum HotkeyIdentifier {
    public static let toggleRecording = "vox.hotkey.toggleRecording"
    public static let injectText = "vox.hotkey.injectText"
    public static let showPopover = "vox.hotkey.showPopover"
}

/// 全局快捷键服务协议 (macOS)
///
/// 提供系统级全局快捷键注册和监听。
@MainActor
public protocol GlobalHotkeyService: AnyObject {

    /// 注册快捷键
    ///
    /// - Parameters:
    ///   - hotkey: 快捷键定义
    ///   - handler: 触发时的回调
    /// - Throws: 注册失败时抛出错误
    func register(_ hotkey: HotkeyDefinition, handler: @escaping @Sendable () -> Void) throws

    /// 注销快捷键
    ///
    /// - Parameter identifier: 快捷键标识符
    func unregister(_ identifier: String)

    /// 注销所有快捷键
    func unregisterAll()

    /// 更新快捷键
    ///
    /// - Parameters:
    ///   - identifier: 快捷键标识符
    ///   - newHotkey: 新的快捷键定义
    /// - Throws: 更新失败时抛出错误
    func update(_ identifier: String, to newHotkey: HotkeyDefinition) throws

    /// 获取已注册的快捷键
    ///
    /// - Parameter identifier: 快捷键标识符
    /// - Returns: 快捷键定义，如果未注册则返回 nil
    func getRegistered(_ identifier: String) -> HotkeyDefinition?

    /// 快捷键触发事件发布者
    var hotkeyTriggeredPublisher: AnyPublisher<String, Never> { get }

    /// 检查快捷键是否可用（未被其他应用占用）
    ///
    /// - Parameter hotkey: 快捷键定义
    /// - Returns: 是否可用
    func isAvailable(_ hotkey: HotkeyDefinition) -> Bool

    /// 注册长按快捷键
    ///
    /// 长按触发时调用 onPress，释放时调用 onRelease。
    /// 长按阈值通常为 0.5 秒。
    ///
    /// - Parameters:
    ///   - hotkey: 快捷键定义
    ///   - onPress: 长按触发时的回调
    ///   - onRelease: 按键释放时的回调
    func registerLongPress(
        _ hotkey: HotkeyDefinition,
        onPress: @escaping @Sendable () async -> Void,
        onRelease: @escaping @Sendable () async -> Void
    )
}
