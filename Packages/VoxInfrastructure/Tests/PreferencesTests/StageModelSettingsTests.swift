import XCTest
@testable import Preferences

final class StageModelSettingsTests: XCTestCase {
    func testDefaultsAndLegacyRefinementMigration() async {
        let suite = "StageModelSettingsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let initial = await StageModelSettings.load(from: store)
        XCTAssertEqual(initial.speech, .realtime)
        XCTAssertEqual(initial.intent, .appleIntelligence)
        XCTAssertEqual(initial.tone, .appleIntelligence)
        await store.setValue("appleIntelligence", for: .llmProvider)
        await store.setValue(true, for: .llmSkipContentAnalysis)
        await store.setValue("batch", for: .speechModel)
        await store.setValue("azureFoundry", for: .intentModel)
        let restored = await StageModelSettings.load(from: store)
        XCTAssertEqual(restored.refinement, .appleIntelligence)
        XCTAssertTrue(restored.skipAnalysis)
        XCTAssertEqual(restored.speech, .batch)
        XCTAssertEqual(restored.intent, .azureFoundry)
        XCTAssertEqual(restored.tone, .appleIntelligence)
    }

    func testDeploymentOverrideRejectsUnsafeOrOversizedValues() {
        for good in ["", "fixture-live", "live.v1_2"] { XCTAssertTrue(StageModelSettings.validDeploymentOverride(good)) }
    }
}
