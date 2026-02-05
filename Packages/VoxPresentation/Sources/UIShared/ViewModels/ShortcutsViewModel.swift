#if os(macOS)
import Foundation
import SwiftUI
import Carbon
import PlatformAdapters
import Preferences

@MainActor
public final class ShortcutsViewModel: ObservableObject {
    @Published public var showPanelKey: FunctionKey = .f7
    @Published public var quickRecordKey: FunctionKey = .f6
    @Published public private(set) var hasConflict: Bool = false

    private let preferences: UserDefaultsPreferencesStore

    public init(preferences: UserDefaultsPreferencesStore = .shared) {
        self.preferences = preferences
    }

    public func load() async {
        let showPanelHotkey = await preferences.getValue(
            for: .showPanelHotkey,
            default: Self.defaultShowPanelHotkey
        )
        let quickRecordHotkey = await preferences.getValue(
            for: .quickRecordHotkey,
            default: Self.defaultQuickRecordHotkey
        )

        showPanelKey = FunctionKey(keyCode: showPanelHotkey.keyCode) ?? .f7
        quickRecordKey = FunctionKey(keyCode: quickRecordHotkey.keyCode) ?? .f6
        updateConflictState()
    }

    public func updateShowPanelKey(_ key: FunctionKey) async {
        showPanelKey = key
        updateConflictState()

        let definition = HotkeyDefinition(
            keyCode: key.keyCode,
            modifiers: 0,
            identifier: HotkeyIdentifier.showPopover
        )
        await preferences.setValue(definition, for: .showPanelHotkey)
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public func updateQuickRecordKey(_ key: FunctionKey) async {
        quickRecordKey = key
        updateConflictState()

        let definition = HotkeyDefinition(
            keyCode: key.keyCode,
            modifiers: 0,
            identifier: HotkeyIdentifier.toggleRecording
        )
        await preferences.setValue(definition, for: .quickRecordHotkey)
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public func resetToDefaults() async {
        await preferences.setValue(Self.defaultShowPanelHotkey, for: .showPanelHotkey)
        await preferences.setValue(Self.defaultQuickRecordHotkey, for: .quickRecordHotkey)
        showPanelKey = .f7
        quickRecordKey = .f6
        updateConflictState()
        NotificationCenter.default.post(name: PreferencesNotification.hotkeysDidChange, object: nil)
    }

    public var showPanelDisplayName: String {
        showPanelKey.label
    }

    public var quickRecordDisplayName: String {
        quickRecordKey.label
    }

    private func updateConflictState() {
        hasConflict = showPanelKey == quickRecordKey
    }

    private static let defaultShowPanelHotkey = HotkeyDefinition(
        keyCode: UInt16(kVK_F7),
        modifiers: 0,
        identifier: HotkeyIdentifier.showPopover
    )

    private static let defaultQuickRecordHotkey = HotkeyDefinition(
        keyCode: UInt16(kVK_F6),
        modifiers: 0,
        identifier: HotkeyIdentifier.toggleRecording
    )
}

public enum FunctionKey: String, CaseIterable, Hashable {
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    public var label: String {
        rawValue.uppercased()
    }

    public var keyCode: UInt16 {
        switch self {
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
        }
    }

    public init?(keyCode: UInt16) {
        switch keyCode {
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
        default: return nil
        }
    }
}
#endif
