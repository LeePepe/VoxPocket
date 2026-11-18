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

    func testRealtimeDeploymentResolutionFollowsSelectedModelAndLegacyFallback() {
        let gpt = StageModelSettings(realtimeDeployment: "fixture-legacy", realtimeStreamModel: .gptRealtime,
                                     gptRealtimeDeployment: "fixture-gpt")
        XCTAssertEqual(gpt.resolvedRealtimeDeployment(gptDefault: "fixture-gpt-default", maiDefault: "fixture-mai"), "fixture-gpt")
        let mai = StageModelSettings(realtimeDeployment: "fixture-legacy", realtimeStreamModel: .maiTranscribe2,
                                     maiRealtimeDeployment: "fixture-mai")
        XCTAssertEqual(mai.resolvedRealtimeDeployment(gptDefault: "fixture-gpt", maiDefault: "fixture-mai-default"), "fixture-mai")
        let fallback = StageModelSettings(realtimeDeployment: "fixture-legacy", realtimeStreamModel: .maiTranscribe2)
        XCTAssertEqual(fallback.resolvedRealtimeDeployment(gptDefault: "fixture-gpt", maiDefault: ""), "fixture-legacy")
    }

    func testMissingStreamModelSelectsMAIWhenOnlyMAIDeploymentExists() async {
        let suite = "StageModelSettingsTests.StreamModel.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        await store.setValue("fixture-mai", for: .maiRealtimeDeployment)
        let settings = await StageModelSettings.load(from: store)
        XCTAssertEqual(settings.realtimeStreamModel, .maiTranscribe2)
    }

    func testDeploymentOverrideRejectsUnsafeOrOversizedValues() {
        for good in ["", "fixture-live", "live.v1_2"] { XCTAssertTrue(StageModelSettings.validDeploymentOverride(good)) }
        for bad in ["../secret", "https://example.invalid", "bad\n", "bad\r", " has spaces ", String(repeating: "a", count: 129)] {
            XCTAssertFalse(StageModelSettings.validDeploymentOverride(bad))
        }
    }
}
