import XCTest
import VoxCore
import VoxLLM
import VoxRefine
import VoxWorkflow
import Preferences
@testable import VoxKitBridge

final class WorkflowPresetMappingTests: XCTestCase {
    func testStageMappingCoversSpeechAndAnalysisCombinations() {
        let speechSelections = SpeechModelSelection.allCases
        let textSelections = TextModelSelection.allCases
        for speech in speechSelections {
            for intent in textSelections {
                for tone in textSelections {
                    let settings = StageModelSettings(speech: speech, intent: intent, tone: tone,
                        refinement: .azureFoundry, skipAnalysis: true)
                    for batchConfigured in [false, true] {
                        for realtimeConfigured in [false, true] {
                            let pipeline = StagePresetMapping.exportedPipeline(settings: settings,
                                batchConfigured: batchConfigured, realtimeConfigured: realtimeConfigured,
                                azureTextConfigured: true)
                            let expectedSpeech: [String]
                            if speech == .appleSpeech || !batchConfigured {
                                expectedSpeech = ["capture.microphone", "speech.apple"]
                            } else if speech == .realtime && realtimeConfigured {
                                expectedSpeech = ["capture.microphone", "speech.apple", "speech.azure.realtime", "speech.azure.batch"]
                            } else {
                                expectedSpeech = ["capture.microphone", "speech.apple", "speech.azure.batch"]
                            }
                            XCTAssertEqual(pipeline.speech, expectedSpeech)
                            let expectedAnalysis = settings.skipAnalysis ? "skipped" : intent.rawValue
                            XCTAssertEqual(pipeline.analysis["intent"], expectedAnalysis)
                            XCTAssertEqual(pipeline.analysis["entities"], expectedAnalysis)
                            XCTAssertEqual(pipeline.analysis["tags"], expectedAnalysis)
                            XCTAssertEqual(pipeline.analysis["params"], expectedAnalysis)
                            XCTAssertEqual(pipeline.analysis["tone"], settings.skipAnalysis ? "skipped" : tone.rawValue)
                            XCTAssertEqual(pipeline.analysis["skip"], nil)
                            XCTAssertEqual(pipeline.refine, "azureFoundry")
                        }
                    }
                }
            }
        }
    }

    func testIOSMappingKeepsAzureProviderWhenTextConfigurationIsMissing() {
        let pipeline = IOSPresetMapping(batchConfigured: true, azureTextConfigured: false).exportedPipeline()
        XCTAssertEqual(pipeline.speech, ["capture.microphone", "speech.apple", "speech.azure.batch"])
        XCTAssertEqual(pipeline.refine, LLMProviderType.azureFoundry.rawValue)
        XCTAssertEqual(pipeline.configFailure, "textModelUnavailable")
        XCTAssertEqual(pipeline.analysis["intent"], LLMProviderType.appleIntelligence.rawValue)
        XCTAssertEqual(pipeline.analysis["tone"], LLMProviderType.appleIntelligence.rawValue)
        XCTAssertEqual(pipeline.analysis["entities"], LLMProviderType.azureFoundry.rawValue)
    }

    @MainActor
    func testIOSPreferenceBindingRetainsProviderForInvalidValuesAndReappliesAnalysis() async {
        let suite = "WorkflowPresetMappingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let center = NotificationCenter()
        let binding = IOSPresetPreferenceBinding(batchConfigured: true, azureTextConfigured: true,
            preferences: store, notificationCenter: center)

        await binding.waitForPendingChanges()
        XCTAssertEqual(binding.currentProvider, .azureFoundry)
        await store.setValue(LLMProviderType.appleIntelligence.rawValue, for: .llmProvider)
        await store.setValue(true, for: .llmSkipContentAnalysis)
        center.post(name: PreferencesNotification.llmAnalysisSettingsDidChange, object: nil)
        await binding.waitForPendingChanges()
        XCTAssertEqual(binding.currentProvider, .appleIntelligence)
        let pipeline = binding.preset.exportedPipeline(batchConfigured: true, realtimeConfigured: false,
            azureTextConfigured: true)
        XCTAssertEqual(pipeline.analysis["entities"], "skipped")
        XCTAssertEqual(pipeline.analysis["intent"], "skipped")
        XCTAssertEqual(pipeline.analysis["tone"], "skipped")
        let entityNode = try! XCTUnwrap(binding.preset.refine.nodes.first { $0.id == "entities" })
        XCTAssertEqual(entityNode.params["analysis.entities.provider"], .string("appleIntelligence"))

        await store.setValue("invalid-provider", for: .llmProvider)
        center.post(name: PreferencesNotification.llmProviderDidChange, object: nil)
        await binding.waitForPendingChanges()
        XCTAssertEqual(binding.currentProvider, .appleIntelligence)
    }

    func testRunnerReportsUnavailableAzureConfigurationAndOwnsRuntimeState() async throws {
        let configuration = WorkflowExecutionConfiguration()
        let main = RefineWorkflowRunner(preset: .hybridAzure, configuration: configuration, azureTextConfigured: false)
        let quick = RefineWorkflowRunner(preset: .hybridAzure, configuration: configuration, azureTextConfigured: false)
        XCTAssertFalse(main.isConfigured)
        XCTAssertFalse(quick.isConfigured)
        XCTAssertNotIdentical(main, quick)
        do {
            _ = try await main.refine(RefinementRequest(text: "fixture"))
            XCTFail("Expected unavailable configuration")
        } catch let error as RefineWorkflowConfigurationError {
            XCTAssertEqual(error, .unavailable)
        }
    }
}
