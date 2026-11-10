#if os(macOS)
import XCTest
import Carbon
import Preferences
@testable import UIShared

@MainActor
final class ShortcutsViewModelTests: XCTestCase {
    func testLoadDefaultsToDirectToTextAndVoiceToTodo() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let viewModel = ShortcutsViewModel(preferences: store)

            await viewModel.load()

            XCTAssertEqual(viewModel.directToTextHotkey.keyCode, UInt16(kVK_Space))
            XCTAssertEqual(viewModel.directToTextHotkey.modifiers, UInt(optionKey))
            XCTAssertEqual(viewModel.directToTextDisplayName, "⌥Space")

            XCTAssertEqual(viewModel.voiceToTodoHotkey.keyCode, UInt16(kVK_Space))
            XCTAssertEqual(viewModel.voiceToTodoHotkey.modifiers, UInt(optionKey | shiftKey))
            XCTAssertEqual(viewModel.voiceToTodoDisplayName, "⌥⇧Space")
            XCTAssertFalse(viewModel.hasConflict)
        }
    }

    func testUpdateCustomSingleKeyAndCombinationHotkeysPersistsAndDetectsExactConflict() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let viewModel = ShortcutsViewModel(preferences: store)
            await viewModel.load()

            // Lofree Num remapped to F19 single key for 录音到剪贴板
            await viewModel.updateDirectToTextHotkey(keyCode: UInt16(kVK_F19), modifiers: 0)
            XCTAssertEqual(viewModel.directToTextHotkey.keyCode, UInt16(kVK_F19))
            XCTAssertEqual(viewModel.directToTextHotkey.modifiers, 0)
            XCTAssertEqual(viewModel.directToTextDisplayName, "F19")
            XCTAssertFalse(viewModel.hasConflict)

            // Same key code (F19) with Option modifier for 录音到 Todo should NOT conflict with bare F19
            let optionMod = UInt(optionKey)
            await viewModel.updateVoiceToTodoHotkey(keyCode: UInt16(kVK_F19), modifiers: optionMod)
            XCTAssertEqual(viewModel.voiceToTodoDisplayName, "⌥F19")
            XCTAssertFalse(viewModel.hasConflict)

            // Matching both keyCode and modifiers triggers conflict
            await viewModel.updateDirectToTextHotkey(keyCode: UInt16(kVK_F19), modifiers: optionMod)
            XCTAssertTrue(viewModel.hasConflict)
            XCTAssertEqual(viewModel.directToTextDisplayName, "⌥F19")

            // Combination key (⌘⇧R) persists across reload
            let cmdShift = UInt(cmdKey | shiftKey)
            await viewModel.updateDirectToTextHotkey(keyCode: UInt16(kVK_ANSI_R), modifiers: cmdShift)
            let reloaded = ShortcutsViewModel(preferences: store)
            await reloaded.load()
            XCTAssertEqual(reloaded.directToTextHotkey.keyCode, UInt16(kVK_ANSI_R))
            XCTAssertEqual(reloaded.directToTextHotkey.modifiers, cmdShift)
            XCTAssertEqual(reloaded.directToTextDisplayName, "⇧⌘R")
            XCTAssertEqual(reloaded.voiceToTodoDisplayName, "⌥F19")
            XCTAssertFalse(reloaded.hasConflict)

            // Reset restores ⌥Space and ⌥⇧Space
            await reloaded.resetToDefaults()
            XCTAssertEqual(reloaded.directToTextDisplayName, "⌥Space")
            XCTAssertEqual(reloaded.voiceToTodoDisplayName, "⌥⇧Space")
            XCTAssertFalse(reloaded.hasConflict)
        }
    }
}
#endif
