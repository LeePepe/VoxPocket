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

    /// 显示字符串（如 "⌘⇧R"、"⌥Space"、"F19"）
    public var displayString: String {
        var parts: [String] = []

        // 兼容 Carbon 修饰键掩码（controlKey=4096, optionKey=2048, shiftKey=512, cmdKey=256）与旧测试位掩码（1 << 0..3）
        let hasControl = (modifiers & 4096 != 0) || (modifiers & (1 << 0) != 0)
        let hasOption = (modifiers & 2048 != 0) || (modifiers & (1 << 1) != 0)
        let hasShift = (modifiers & 512 != 0) || (modifiers & (1 << 2) != 0)
        let hasCommand = (modifiers & 256 != 0) || (modifiers & (1 << 3) != 0)

        if hasControl { parts.append("⌃") }
        if hasOption { parts.append("⌥") }
        if hasShift { parts.append("⇧") }
        if hasCommand { parts.append("⌘") }

        parts.append(Self.keyLabel(for: keyCode))
        return parts.joined()
    }

    /// 将 macOS Carbon 键码映射为可读标签
    public static func keyLabel(for keyCode: UInt16) -> String {
        if let fKey = functionAndSpecialKeyLabels[keyCode] {
            return fKey
        }
        if let alnum = alphanumericAndPunctuationLabels[keyCode] {
            return alnum
        }
        return "Key(\(keyCode))"
    }

    private static let functionAndSpecialKeyLabels: [UInt16: String] = [
        63: "Fn",
        49: "Space",
        36: "Return",
        48: "Tab",
        51: "Delete",
        117: "ForwardDelete",
        53: "Esc",
        71: "Num",
        76: "Enter",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        115: "Home",
        119: "End",
        116: "PageUp",
        121: "PageDown",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        105: "F13",
        107: "F14",
        113: "F15",
        106: "F16",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20"
    ]

    private static let alphanumericAndPunctuationLabels: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9",
        82: "Num0", 83: "Num1", 84: "Num2", 85: "Num3", 86: "Num4",
        87: "Num5", 88: "Num6", 89: "Num7", 91: "Num8", 92: "Num9",
        65: "Num.", 67: "Num*", 69: "Num+", 75: "Num/", 78: "Num-", 81: "Num=",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\",
        43: ",", 44: "/", 47: ".", 50: "`"
    ]
}

/// 预定义的快捷键标识符
public enum HotkeyIdentifier {
    public static let toggleRecording = "vox.hotkey.toggleRecording"
    public static let injectText = "vox.hotkey.injectText"
    public static let showPopover = "vox.hotkey.showPopover"
    public static let directToText = "vox.hotkey.directToText"
    public static let voiceToTodo = "vox.hotkey.voiceToTodo"
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
    /// 当 keyCode 为 `kVK_Function`（Fn）时，按下即调用 onPress，抬起即调用 onRelease。
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
