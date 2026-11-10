#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Carbon
import PlatformAdapters
import Preferences

@MainActor
public final class ShortcutsViewModel: ObservableObject {
    @Published public private(set) var directToTextHotkey: HotkeyDefinition = ShortcutsViewModel.defaultDirectToTextHotkey
    @Published public private(set) var voiceToTodoHotkey: HotkeyDefinition = ShortcutsViewModel.defaultVoiceToTodoHotkey
    @Published public private(set) var hasConflict: Bool = false

    private let preferences: UserDefaultsPreferencesStore

    public init(preferences: UserDefaultsPreferencesStore = .shared) {
        self.preferences = preferences
    }

    public func load() async {
        let loadedDirectToTextHotkey = await preferences.getValue(
            for: .directToTextHotkey,
            default: Self.defaultDirectToTextHotkey
        )
        let loadedVoiceToTodoHotkey = await preferences.getValue(
            for: .voiceToTodoHotkey,
            default: Self.defaultVoiceToTodoHotkey
        )

        directToTextHotkey = loadedDirectToTextHotkey
        voiceToTodoHotkey = loadedVoiceToTodoHotkey
        updateConflictState()
    }

    public func updateDirectToTextHotkey(keyCode: UInt16, modifiers: UInt) async {
        let normalizedModifiers = keyCode == UInt16(kVK_Function) ? 0 : modifiers
        let definition = HotkeyDefinition(
            keyCode: keyCode,
            modifiers: normalizedModifiers,
            identifier: HotkeyIdentifier.directToText
        )
        directToTextHotkey = definition
        updateConflictState()
        await preferences.setValue(definition, for: .directToTextHotkey)
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public func updateVoiceToTodoHotkey(keyCode: UInt16, modifiers: UInt) async {
        let normalizedModifiers = keyCode == UInt16(kVK_Function) ? 0 : modifiers
        let definition = HotkeyDefinition(
            keyCode: keyCode,
            modifiers: normalizedModifiers,
            identifier: HotkeyIdentifier.voiceToTodo
        )
        voiceToTodoHotkey = definition
        updateConflictState()
        await preferences.setValue(definition, for: .voiceToTodoHotkey)
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public func resetToDefaults() async {
        await preferences.setValue(Self.defaultDirectToTextHotkey, for: .directToTextHotkey)
        await preferences.setValue(Self.defaultVoiceToTodoHotkey, for: .voiceToTodoHotkey)
        directToTextHotkey = Self.defaultDirectToTextHotkey
        voiceToTodoHotkey = Self.defaultVoiceToTodoHotkey
        updateConflictState()
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public var directToTextDisplayName: String {
        directToTextHotkey.displayString
    }

    public var voiceToTodoDisplayName: String {
        voiceToTodoHotkey.displayString
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
        hasConflict = directToTextHotkey.keyCode == voiceToTodoHotkey.keyCode
            && directToTextHotkey.modifiers == voiceToTodoHotkey.modifiers
    }

    public static let defaultDirectToTextHotkey = HotkeyDefinition(
        keyCode: UInt16(kVK_Space),
        modifiers: UInt(optionKey),
        identifier: HotkeyIdentifier.directToText
    )

    public static let defaultVoiceToTodoHotkey = HotkeyDefinition(
        keyCode: UInt16(kVK_Space),
        modifiers: UInt(optionKey | shiftKey),
        identifier: HotkeyIdentifier.voiceToTodo
    )
}
#endif
