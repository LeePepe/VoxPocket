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
}
#endif
