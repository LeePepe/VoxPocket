import XCTest
import Preferences
@testable import UIShared

@MainActor
final class LLMProviderSettingsViewModelTests: XCTestCase {
    func testStageSelectionsPersistIndependentlyAndDefaultToRealtime() async {
        let suite = "StageSettings.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        let model = LLMProviderSettingsViewModel(preferences: store)
        await model.load()
        XCTAssertEqual(model.speechModel, .realtime)
        XCTAssertTrue(model.hasSpeechWarning)
        XCTAssertTrue(model.speechStatus.contains("回退"))
        await model.updateSpeechModel(.batch)
        await model.updateIntentModel(.azureFoundry)
        await model.updateToneModel(.appleIntelligence)
        await model.updateProvider(.appleIntelligence)
        await model.updateSkipContentAnalysis(true)
        let restored = LLMProviderSettingsViewModel(preferences: store)
        await restored.load()
        XCTAssertEqual(restored.speechModel, .batch)
        XCTAssertEqual(restored.intentModel, .azureFoundry)
        XCTAssertEqual(restored.toneModel, .appleIntelligence)
        XCTAssertEqual(restored.selectedProvider, .appleIntelligence)
        XCTAssertTrue(restored.skipContentAnalysis)
    }

    func testDeploymentMustBeSavedAndValidBeforeShowingReady() async {
        let suite = "StageDeployment.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        let model = LLMProviderSettingsViewModel(preferences: store, availability: .init(
            batchConfigured: true, realtimeCredentialsConfigured: true, textConfigured: true, textModelName: "fixture-text"
        ))
        await model.load()
        XCTAssertFalse(model.realtimeReady)
        model.realtimeDeploymentDraft = "fixture-live"
        XCTAssertFalse(model.realtimeReady)
        await model.load()
        XCTAssertEqual(model.realtimeDeploymentDraft, "fixture-live")
        await model.saveRealtimeDeployment()
        XCTAssertTrue(model.realtimeReady)
        model.realtimeDeploymentDraft = "https://invalid.example"
        await model.saveRealtimeDeployment()
        let stored: String? = await store.getValue(for: .realtimeDeployment)
        XCTAssertEqual(stored, "fixture-live")
        XCTAssertTrue(model.deploymentMessage?.contains("部署名") == true)
    }

    func testLoadDefaultProviderIsAzureFoundry() async {
        let suite = "LLMProviderSettingsViewModelTests.default"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let viewModel = LLMProviderSettingsViewModel(preferences: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.selectedProvider, .azureFoundry)
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

    func testSavedAppleSelectionIsNotOverwrittenByNewDefault() async {
        let suite = "LLMProviderSettingsViewModelTests.savedApple"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        await store.setValue(LLMProviderSelection.appleIntelligence.rawValue, for: .llmProvider)
        let viewModel = LLMProviderSettingsViewModel(preferences: store)
        await viewModel.load()
        XCTAssertEqual(viewModel.selectedProvider, .appleIntelligence)
    }
}
