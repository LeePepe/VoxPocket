#if os(macOS)
import XCTest
import Carbon
import Preferences
@testable import UIShared

@MainActor
final class ShortcutsViewModelTests: XCTestCase {
    func testLoadDefaultsQuickRecordToFn() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let viewModel = ShortcutsViewModel(preferences: store)

            await viewModel.load()

            XCTAssertEqual(viewModel.quickRecordKey, .fn)
        }
    }

    func testFunctionKeyInitSupportsFn() {
        XCTAssertEqual(FunctionKey(keyCode: UInt16(kVK_Function)), .fn)
    }

    func testFunctionKeySupportsF13ThroughF20AndNumPreset() {
        XCTAssertEqual(FunctionKey(keyCode: UInt16(kVK_F13)), .f13)
        XCTAssertEqual(FunctionKey(keyCode: UInt16(kVK_F19)), .f19)
        XCTAssertEqual(FunctionKey.f19.keyCode, UInt16(kVK_F19))
        XCTAssertEqual(FunctionKey.f19.label, "F19")
        XCTAssertEqual(FunctionKey(keyCode: UInt16(kVK_F20)), .f20)
        XCTAssertEqual(FunctionKey(keyCode: UInt16(kVK_ANSI_KeypadClear)), .num)
        XCTAssertEqual(FunctionKey.num.label, "NUM")
    }

    func testUpdateCustomAndCombinationHotkeysPersistsAndDetectsExactConflict() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let viewModel = ShortcutsViewModel(preferences: store)
            await viewModel.load()

            // Lofree Num remapped to F19 single key
            await viewModel.updateQuickRecordHotkey(keyCode: UInt16(kVK_F19), modifiers: 0)
            XCTAssertEqual(viewModel.quickRecordKey, .f19)
            XCTAssertEqual(viewModel.quickRecordDisplayName, "F19")
            XCTAssertFalse(viewModel.hasConflict)

            // Same key code (F19) with Option modifier should NOT conflict with bare F19
            let optionMod = UInt(optionKey)
            await viewModel.updateShowPanelHotkey(keyCode: UInt16(kVK_F19), modifiers: optionMod)
            XCTAssertEqual(viewModel.showPanelDisplayName, "⌥F19")
            XCTAssertFalse(viewModel.hasConflict)

            // Matching both keyCode and modifiers triggers conflict
            await viewModel.updateQuickRecordHotkey(keyCode: UInt16(kVK_F19), modifiers: optionMod)
            XCTAssertTrue(viewModel.hasConflict)
            XCTAssertEqual(viewModel.quickRecordDisplayName, "⌥F19")

            // Combination key (⌘⇧R) persists across reload
            let cmdShift = UInt(cmdKey | shiftKey)
            await viewModel.updateQuickRecordHotkey(keyCode: UInt16(kVK_ANSI_R), modifiers: cmdShift)
            let reloaded = ShortcutsViewModel(preferences: store)
            await reloaded.load()
            XCTAssertEqual(reloaded.quickRecordHotkey.keyCode, UInt16(kVK_ANSI_R))
            XCTAssertEqual(reloaded.quickRecordHotkey.modifiers, cmdShift)
            XCTAssertEqual(reloaded.quickRecordDisplayName, "⇧⌘R")
            XCTAssertFalse(reloaded.hasConflict)
        }
    }
}
#endif
