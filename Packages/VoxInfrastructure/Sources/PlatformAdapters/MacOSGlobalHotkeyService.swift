#if os(macOS)
import Foundation
import Combine
import Carbon
import AppKit
import LokiKit

/// macOS 全局快捷键服务实现
///
/// 使用 Carbon Event Manager API 注册系统级全局快捷键。
/// 支持普通点击和长按两种模式。
@MainActor
public final class MacOSGlobalHotkeyService: GlobalHotkeyService {

    // MARK: - 类型

    private struct HotkeyInfo {
        let definition: HotkeyDefinition
        let handler: @Sendable () -> Void
        var hotkeyRef: EventHotKeyRef?
    }

    private struct LongPressInfo {
        let definition: HotkeyDefinition
        let onPress: @Sendable () async -> Void
        let onRelease: @Sendable () async -> Void
        var isPressed: Bool = false
        var keyDownTime: Date?
        var hasTriggeredPress: Bool = false
    }

    // MARK: - 常量

    /// 长按检测阈值（秒）
    private static let longPressDuration: TimeInterval = 0.5

    // MARK: - 属性

    private var registeredHotkeys: [String: HotkeyInfo] = [:]
    private var longPressHotkeys: [String: LongPressInfo] = [:]
    private var hotkeyIdToIdentifier: [UInt32: String] = [:]
    private var nextHotkeyId: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let logger: Logger = PrintLogger(subsystem: "GlobalHotkey")

    private let hotkeySubject = PassthroughSubject<String, Never>()
    public var hotkeyTriggeredPublisher: AnyPublisher<String, Never> {
        hotkeySubject.eraseToAnyPublisher()
    }

    // MARK: - 单例

    public static let shared = MacOSGlobalHotkeyService()

    // MARK: - 初始化

    private init() {
        setupCarbonEventHandler()
        setupKeyMonitors()
    }

    // MARK: - 清理

    /// 清理所有资源（应在应用退出时调用）
    public func cleanup() {
        unregisterAll()
        removeEventHandler()
        removeKeyMonitors()
    }

    // MARK: - Carbon Event Handler 设置

    private func setupCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<MacOSGlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()

                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                if status == noErr {
                    Task { @MainActor in
                        service.handleHotkeyTriggered(id: hotkeyID.id)
                    }
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if handlerResult != noErr {
            logger.log(.debug, "Failed to install Carbon event handler", context: [
                "status": handlerResult
            ])
        }
    }

    private func removeEventHandler() {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    // MARK: - NSEvent 监听器（用于长按检测）

    private func setupKeyMonitors() {
        // 全局键盘事件监听
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event, source: "global")
            }
        }

        // 本地键盘事件监听（当应用在前台时）
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event, source: "local")
            }
            return event
        }
    }

    private func removeKeyMonitors() {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - 事件处理

    private func handleHotkeyTriggered(id: UInt32) {
        guard let identifier = hotkeyIdToIdentifier[id],
              let info = registeredHotkeys[identifier] else {
            return
        }

        logger.log(.debug, "Hotkey triggered", context: ["identifier": identifier])
        hotkeySubject.send(identifier)
        info.handler()
    }

    private func handleKeyEvent(_ event: NSEvent, source: String = "unknown") {
        let keyCode = event.keyCode
        let modifiers = carbonModifiers(from: event.modifierFlags)
        let functionKeyCode = UInt16(kVK_Function)

        // 查找匹配的长按快捷键
        for (identifier, var info) in longPressHotkeys {
            // Fn 键是 flagsChanged 事件：按下即开始，抬起即结束
            if info.definition.keyCode == functionKeyCode {
                guard keyCode == functionKeyCode, event.type == .flagsChanged else {
                    continue
                }

                let isFunctionPressed = event.modifierFlags.contains(.function)
                if isFunctionPressed && !info.isPressed {
                    info.isPressed = true
                    info.keyDownTime = Date()
                    info.hasTriggeredPress = true
                    longPressHotkeys[identifier] = info

                    logger.log(.debug, "Function key down", context: ["identifier": identifier, "source": source])
                    Task {
                        await info.onPress()
                    }
                } else if isFunctionPressed && info.isPressed {
                    logger.log(.debug, "Function key down IGNORED (already pressed)", context: ["identifier": identifier, "source": source])
                } else if !isFunctionPressed && info.isPressed {
                    info.isPressed = false
                    info.keyDownTime = nil
                    let shouldRelease = info.hasTriggeredPress
                    info.hasTriggeredPress = false
                    longPressHotkeys[identifier] = info

                    logger.log(.debug, "Function key up", context: ["identifier": identifier, "source": source, "will_release": shouldRelease])
                    if shouldRelease {
                        Task {
                            await info.onRelease()
                        }
                    }
                } else if !isFunctionPressed && !info.isPressed {
                    logger.log(.debug, "Function key up IGNORED (already released)", context: ["identifier": identifier, "source": source])
                }
                continue
            }

            guard info.definition.keyCode == keyCode,
                  info.definition.modifiers == modifiers else {
                continue
            }

            switch event.type {
            case .keyDown:
                if !info.isPressed {
                    info.isPressed = true
                    info.keyDownTime = Date()
                    info.hasTriggeredPress = false
                    longPressHotkeys[identifier] = info

                    logger.log(.debug, "Long-press key down", context: ["identifier": identifier])

                    // 延迟后检查是否仍在按住
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(Self.longPressDuration))
                        guard let self = self,
                              let currentInfo = self.longPressHotkeys[identifier],
                              currentInfo.isPressed,
                              let keyDownTime = currentInfo.keyDownTime,
                              Date().timeIntervalSince(keyDownTime) >= Self.longPressDuration else {
                            return
                        }

                        var updatedInfo = currentInfo
                        guard !updatedInfo.hasTriggeredPress else { return }
                        updatedInfo.hasTriggeredPress = true
                        self.longPressHotkeys[identifier] = updatedInfo

                        self.logger.log(.debug, "Long-press triggered", context: ["identifier": identifier])
                        await updatedInfo.onPress()
                    }
                }

            case .keyUp:
                if info.isPressed {
                    info.isPressed = false
                    info.keyDownTime = nil
                    let shouldRelease = info.hasTriggeredPress
                    info.hasTriggeredPress = false
                    longPressHotkeys[identifier] = info

                    logger.log(.debug, "Long-press key up", context: [
                        "identifier": identifier,
                        "should_release": shouldRelease
                    ])

                    if shouldRelease {
                        Task {
                            await info.onRelease()
                        }
                    }
                }

            default:
                break
            }
        }
    }

    // MARK: - GlobalHotkeyService 协议实现

    public func register(_ hotkey: HotkeyDefinition, handler: @escaping @Sendable () -> Void) throws {
        // 先注销已有的同标识符快捷键
        unregister(hotkey.identifier)

        let hotkeyId = nextHotkeyId
        nextHotkeyId += 1

        var hotkeyRef: EventHotKeyRef?
        var hotkeyID = EventHotKeyID(signature: OSType(0x564F5850), id: hotkeyId)  // "VOXP"

        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            UInt32(hotkey.modifiers),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, hotkeyRef != nil else {
            throw GlobalHotkeyError.registrationFailed(status: status)
        }

        let info = HotkeyInfo(definition: hotkey, handler: handler, hotkeyRef: hotkeyRef)
        registeredHotkeys[hotkey.identifier] = info
        hotkeyIdToIdentifier[hotkeyId] = hotkey.identifier

        logger.log(.debug, "Registered hotkey", context: [
            "identifier": hotkey.identifier,
            "display": hotkey.displayString
        ])
    }

    public func unregister(_ identifier: String) {
        // 注销普通快捷键
        if let info = registeredHotkeys.removeValue(forKey: identifier) {
            if let ref = info.hotkeyRef {
                UnregisterEventHotKey(ref)
            }
            hotkeyIdToIdentifier = hotkeyIdToIdentifier.filter { $0.value != identifier }
            logger.log(.debug, "Unregistered hotkey", context: ["identifier": identifier])
        }

        // 注销长按快捷键
        longPressHotkeys.removeValue(forKey: identifier)
    }

    public func unregisterAll() {
        for identifier in registeredHotkeys.keys {
            unregister(identifier)
        }
        longPressHotkeys.removeAll()
    }

    public func update(_ identifier: String, to newHotkey: HotkeyDefinition) throws {
        guard let info = registeredHotkeys[identifier] else {
            throw GlobalHotkeyError.notFound(identifier: identifier)
        }

        let handler = info.handler
        unregister(identifier)

        var updatedHotkey = newHotkey
        // 保持原标识符
        if updatedHotkey.identifier != identifier {
            updatedHotkey = HotkeyDefinition(
                keyCode: newHotkey.keyCode,
                modifiers: newHotkey.modifiers,
                identifier: identifier
            )
        }

        try register(updatedHotkey, handler: handler)
    }

    public func getRegistered(_ identifier: String) -> HotkeyDefinition? {
        registeredHotkeys[identifier]?.definition ?? longPressHotkeys[identifier]?.definition
    }

    public func isAvailable(_ hotkey: HotkeyDefinition) -> Bool {
        // 检查是否与已注册的快捷键冲突
        for (_, info) in registeredHotkeys {
            if info.definition.keyCode == hotkey.keyCode &&
               info.definition.modifiers == hotkey.modifiers &&
               info.definition.identifier != hotkey.identifier {
                return false
            }
        }
        for (_, info) in longPressHotkeys {
            if info.definition.keyCode == hotkey.keyCode &&
               info.definition.modifiers == hotkey.modifiers &&
               info.definition.identifier != hotkey.identifier {
                return false
            }
        }
        return true
    }

    // MARK: - 长按快捷键支持

    /// 注册长按快捷键
    ///
    /// - Parameters:
    ///   - hotkey: 快捷键定义
    ///   - onPress: 长按触发时的回调
    ///   - onRelease: 按键释放时的回调
    public func registerLongPress(
        _ hotkey: HotkeyDefinition,
        onPress: @escaping @Sendable () async -> Void,
        onRelease: @escaping @Sendable () async -> Void
    ) {
        // 先注销已有的同标识符快捷键
        unregister(hotkey.identifier)

        let info = LongPressInfo(
            definition: hotkey,
            onPress: onPress,
            onRelease: onRelease
        )
        longPressHotkeys[hotkey.identifier] = info

        logger.log(.debug, "Registered long-press hotkey", context: [
            "identifier": hotkey.identifier,
            "display": hotkey.displayString
        ])
    }

    // MARK: - 辅助方法

    /// 将 NSEvent.ModifierFlags 转换为 Carbon 修饰键
    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt {
        var modifiers: UInt = 0
        if flags.contains(.control) { modifiers |= UInt(controlKey) }
        if flags.contains(.option) { modifiers |= UInt(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt(cmdKey) }
        return modifiers
    }
}

// MARK: - 错误类型

public enum GlobalHotkeyError: LocalizedError {
    case registrationFailed(status: OSStatus)
    case notFound(identifier: String)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Failed to register hotkey: \(status)"
        case .notFound(let identifier):
            return "Hotkey not found: \(identifier)"
        }
    }
}
#endif
