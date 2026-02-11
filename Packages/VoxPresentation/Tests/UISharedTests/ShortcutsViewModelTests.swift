#if os(macOS)
import XCTest
import Carbon
import Preferences
@testable import UIShared

@MainActor
final class ShortcutsViewModelTests: XCTestCase {
    func testLoadDefaultsQuickRecordToFn() async {
        let defaults = UserDefaults(suiteName: "ShortcutsViewModelTests.defaultFn")!
        defaults.removePersistentDomain(forName: "ShortcutsViewModelTests.defaultFn")
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let viewModel = ShortcutsViewModel(preferences: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.quickRecordKey, .fn)
    }

    func testFunctionKeyInitSupportsFn() {
        XCTAssertEqual(FunctionKey(keyCode: UInt16(kVK_Function)), .fn)
    }
}
#endif
