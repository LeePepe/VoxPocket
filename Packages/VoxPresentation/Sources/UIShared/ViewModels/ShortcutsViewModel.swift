#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Carbon
import PlatformAdapters
import Preferences

@MainActor
public final class ShortcutsViewModel: ObservableObject {
    @Published public var showPanelKey: FunctionKey = .f7
    @Published public var quickRecordKey: FunctionKey = .fn
    @Published public private(set) var showPanelHotkey: HotkeyDefinition = ShortcutsViewModel.defaultShowPanelHotkey
    @Published public private(set) var quickRecordHotkey: HotkeyDefinition = ShortcutsViewModel.defaultQuickRecordHotkey
    @Published public private(set) var hasConflict: Bool = false

    private let preferences: UserDefaultsPreferencesStore

    public init(preferences: UserDefaultsPreferencesStore = .shared) {
        self.preferences = preferences
    }

    public func load() async {
        let loadedShowPanelHotkey = await preferences.getValue(
            for: .showPanelHotkey,
            default: Self.defaultShowPanelHotkey
        )
        let loadedQuickRecordHotkey = await preferences.getValue(
            for: .quickRecordHotkey,
            default: Self.defaultQuickRecordHotkey
        )

        showPanelHotkey = loadedShowPanelHotkey
        quickRecordHotkey = loadedQuickRecordHotkey
        showPanelKey = FunctionKey(keyCode: loadedShowPanelHotkey.keyCode) ?? .f7
        quickRecordKey = FunctionKey(keyCode: loadedQuickRecordHotkey.keyCode) ?? .fn
        updateConflictState()
    }

    public func updateShowPanelKey(_ key: FunctionKey) async {
        await updateShowPanelHotkey(keyCode: key.keyCode, modifiers: 0)
    }

    public func updateQuickRecordKey(_ key: FunctionKey) async {
        await updateQuickRecordHotkey(keyCode: key.keyCode, modifiers: 0)
    }

    public func updateShowPanelHotkey(keyCode: UInt16, modifiers: UInt) async {
        let normalizedModifiers = keyCode == UInt16(kVK_Function) ? 0 : modifiers
        let definition = HotkeyDefinition(
            keyCode: keyCode,
            modifiers: normalizedModifiers,
            identifier: HotkeyIdentifier.showPopover
        )
        showPanelHotkey = definition
        if let preset = FunctionKey(keyCode: keyCode) {
            showPanelKey = preset
        }
        updateConflictState()
        await preferences.setValue(definition, for: .showPanelHotkey)
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public func updateQuickRecordHotkey(keyCode: UInt16, modifiers: UInt) async {
        let normalizedModifiers = keyCode == UInt16(kVK_Function) ? 0 : modifiers
        let definition = HotkeyDefinition(
            keyCode: keyCode,
            modifiers: normalizedModifiers,
            identifier: HotkeyIdentifier.toggleRecording
        )
        quickRecordHotkey = definition
        if let preset = FunctionKey(keyCode: keyCode) {
            quickRecordKey = preset
        }
        updateConflictState()
        await preferences.setValue(definition, for: .quickRecordHotkey)
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public func resetToDefaults() async {
        await preferences.setValue(Self.defaultShowPanelHotkey, for: .showPanelHotkey)
        await preferences.setValue(Self.defaultQuickRecordHotkey, for: .quickRecordHotkey)
        showPanelHotkey = Self.defaultShowPanelHotkey
        quickRecordHotkey = Self.defaultQuickRecordHotkey
        showPanelKey = .f7
        quickRecordKey = .fn
        updateConflictState()
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public var showPanelDisplayName: String {
        if showPanelHotkey.modifiers == 0, let preset = FunctionKey(keyCode: showPanelHotkey.keyCode) {
            return preset.label
        }
        return showPanelHotkey.displayString
    }

    public var quickRecordDisplayName: String {
        if quickRecordHotkey.modifiers == 0, let preset = FunctionKey(keyCode: quickRecordHotkey.keyCode) {
            return preset.label
        }
        return quickRecordHotkey.displayString
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt {
        var modifiers: UInt = 0
        if flags.contains(.control) { modifiers |= UInt(controlKey) }
        if flags.contains(.option) { modifiers |= UInt(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt(cmdKey) }
        return modifiers
    }

    private func updateConflictState() {
        hasConflict = showPanelHotkey.keyCode == quickRecordHotkey.keyCode
            && showPanelHotkey.modifiers == quickRecordHotkey.modifiers
    }

    private static let defaultShowPanelHotkey = HotkeyDefinition(
        keyCode: UInt16(kVK_F7),
        modifiers: 0,
        identifier: HotkeyIdentifier.showPopover
    )

    private static let defaultQuickRecordHotkey = HotkeyDefinition(
        keyCode: UInt16(kVK_Function),
        modifiers: 0,
        identifier: HotkeyIdentifier.toggleRecording
    )
}

public enum FunctionKey: String, CaseIterable, Hashable {
    case fn, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case f13, f14, f15, f16, f17, f18, f19, f20, num

    public var label: String {
        rawValue.uppercased()
    }

    public var keyCode: UInt16 {
        switch self {
        case .fn: return UInt16(kVK_Function)
        case .f1: return UInt16(kVK_F1)
        case .f2: return UInt16(kVK_F2)
        case .f3: return UInt16(kVK_F3)
        case .f4: return UInt16(kVK_F4)
        case .f5: return UInt16(kVK_F5)
        case .f6: return UInt16(kVK_F6)
        case .f7: return UInt16(kVK_F7)
        case .f8: return UInt16(kVK_F8)
        case .f9: return UInt16(kVK_F9)
        case .f10: return UInt16(kVK_F10)
        case .f11: return UInt16(kVK_F11)
        case .f12: return UInt16(kVK_F12)
        case .f13: return UInt16(kVK_F13)
        case .f14: return UInt16(kVK_F14)
        case .f15: return UInt16(kVK_F15)
        case .f16: return UInt16(kVK_F16)
        case .f17: return UInt16(kVK_F17)
        case .f18: return UInt16(kVK_F18)
        case .f19: return UInt16(kVK_F19)
        case .f20: return UInt16(kVK_F20)
        case .num: return UInt16(kVK_ANSI_KeypadClear)
        }
    }

    public init?(keyCode: UInt16) {
        switch keyCode {
        case UInt16(kVK_Function): self = .fn
        case UInt16(kVK_F1): self = .f1
        case UInt16(kVK_F2): self = .f2
        case UInt16(kVK_F3): self = .f3
        case UInt16(kVK_F4): self = .f4
        case UInt16(kVK_F5): self = .f5
        case UInt16(kVK_F6): self = .f6
        case UInt16(kVK_F7): self = .f7
        case UInt16(kVK_F8): self = .f8
        case UInt16(kVK_F9): self = .f9
        case UInt16(kVK_F10): self = .f10
        case UInt16(kVK_F11): self = .f11
        case UInt16(kVK_F12): self = .f12
        case UInt16(kVK_F13): self = .f13
        case UInt16(kVK_F14): self = .f14
        case UInt16(kVK_F15): self = .f15
        case UInt16(kVK_F16): self = .f16
        case UInt16(kVK_F17): self = .f17
        case UInt16(kVK_F18): self = .f18
        case UInt16(kVK_F19): self = .f19
        case UInt16(kVK_F20): self = .f20
        case UInt16(kVK_ANSI_KeypadClear): self = .num
        default: return nil
        }
    }
}
#endif
