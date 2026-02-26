import XCTest
import Preferences
@testable import UIShared

@MainActor
final class LLMProviderSettingsViewModelTests: XCTestCase {
    func testLoadDefaultProviderIsAppleIntelligence() async {
        let suite = "LLMProviderSettingsViewModelTests.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let viewModel = LLMProviderSettingsViewModel(preferences: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.selectedProvider, .appleIntelligence)
    }

    func testUpdateProviderPersistsSelection() async {
        let suite = "LLMProviderSettingsViewModelTests.persist"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let viewModel = LLMProviderSettingsViewModel(preferences: store)

        await viewModel.updateProvider(.azureFoundry)

        let stored: String? = await store.getValue(for: .llmProvider)
        XCTAssertEqual(stored, LLMProviderSelection.azureFoundry.rawValue)
    }
}
