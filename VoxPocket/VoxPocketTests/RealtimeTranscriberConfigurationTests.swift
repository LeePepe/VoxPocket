import Foundation
import Testing
import Preferences
import LLMKit
import TranscriptionKit
@testable import VoxPocket

struct RealtimeTranscriberConfigurationTests {
    private var environment: [String: String] {
        ["AZURE_OPENAI_ENDPOINT": "https://example.invalid", "AZURE_API_KEY": "fixture-key"]
    }

    @MainActor @Test func realtimeIsOptInAndMacOSOnly() {
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: environment) == nil)
        var values = environment
        values["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "fixture-live"
        #if os(macOS)
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values) != nil)
        #else
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values) == nil)
        #endif
    }

    @MainActor @Test func invalidRealtimeConfigurationKeepsBatchAvailable() {
        var values = environment
        values["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "../invalid"
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values) == nil)
        #expect(LLMAppConfig.transcriptionConfig(environment: values) != nil)
        values["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "fixture-live"
        values["AZURE_OPENAI_ENDPOINT"] = "https://example.invalid/path"
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values) == nil)
    }

    @MainActor @Test func legacySpeechKeyStillWorksAndRefinementIsUnchanged() {
        var values = environment
        values.removeValue(forKey: "AZURE_API_KEY")
        values["whisperkey"] = "fixture-speech-key"
        values["kimikey"] = "fixture-text-key"
        let before = LLMAppConfig.refinementAPIKey(environment: values)
        values["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "fixture-live"
        #if os(macOS)
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values) != nil)
        #endif
        #expect(LLMAppConfig.refinementAPIKey(environment: values) == before)
    }

    @MainActor @Test func stageSelectionsDriveTheActualSpeechRoute() {
        var values = environment
        values["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "fixture-live"
        #if os(macOS)
        #expect(StageModelRouting.resolvedSpeechModel(settings: .init(), environment: values) == .realtime)
        #else
        #expect(StageModelRouting.resolvedSpeechModel(settings: .init(), environment: values) == .batch)
        #endif
        #expect(StageModelRouting.resolvedSpeechModel(settings: .init(speech: .batch), environment: values) == .batch)
        #expect(StageModelRouting.resolvedSpeechModel(settings: .init(speech: .appleSpeech), environment: values) == .appleSpeech)
        #expect(StageModelRouting.resolvedSpeechModel(settings: .init(), environment: environment) == .batch)
        #expect(StageModelRouting.resolvedSpeechModel(settings: .init(), environment: [:]) == .appleSpeech)
    }

    @MainActor @Test func settingsDeploymentEnablesLegacyConfigurationWithoutChangingKeys() {
        let settings = StageModelSettings(realtimeDeployment: "fixture-live-override")
        #if os(macOS)
        #expect(StageModelRouting.resolvedSpeechModel(settings: settings, environment: environment) == .realtime)
        #endif
        let availability = StageModelRouting.availability(environment: environment)
        #expect(availability.batchConfigured)
        #expect(availability.realtimeCredentialsConfigured)
        #expect(availability.realtimeDeployment.isEmpty)
        #expect(availability.textModelName == "默认文本模型")
    }

    @MainActor @Test func analysisRoutingUsesIndependentIntentAndToneSelections() {
        let settings = StageModelSettings(intent: .azureFoundry, tone: .appleIntelligence, refinement: .azureFoundry)
        let options = StageModelRouting.analysisOptions(settings: settings)
        #expect(options["analysis.intent.provider"] == "azureFoundry")
        #expect(options["analysis.entities.provider"] == "azureFoundry")
        #expect(options["analysis.tone.provider"] == "appleIntelligence")
    }

    @MainActor @Test func unavailableTextConfigurationDoesNotBlockSpeechSetupOrUseWrongTextModel() async {
        let text = DefaultStageTextModelService(azureFoundryConfig: nil, settings: .init())
        let speech = StageModelRouting.prepareSession(settings: .init(), environment: [:], beforeSession: { text.configure($0) })
        #expect(speech is AppleSpeechTranscriber)
        #expect(text.currentProvider == nil)
        do {
            _ = try await text.refine(.init(text: "synthetic input"))
            Issue.record("Unconfigured selected cloud model must not silently use Apple")
        } catch {
            #expect(error is DefaultStageTextModelService.ConfigurationError)
        }
    }

    @MainActor @Test func recordingChannelsOwnDifferentTextSnapshots() throws {
        let config = LLMProviderConfig(providerType: .azureFoundry, apiKey: "fixture-key",
                                       baseURL: URL(string: "https://example.invalid"), modelIdentifier: "fixture-text")
        let channels = StageTextModelServices(azureConfig: config, settings: .init())
        #expect(channels.main !== channels.quick)
        let mainProvider = try #require(channels.main.currentProvider)
        #expect(mainProvider !== channels.quick.currentProvider)
        channels.quick.configure(.init(refinement: .appleIntelligence))
        #expect(channels.main.currentProvider === mainProvider)
        #expect(channels.main.currentProviderType == .azureFoundry)
        #expect(channels.quick.currentProviderType == .appleIntelligence)
        channels.main.configure(.init(refinement: .appleIntelligence))
        #expect(mainProvider.config.modelIdentifier == "fixture-text")
        #expect(channels.main.currentProvider !== mainProvider)
    }

    @MainActor @Test func unconfiguredTextModelNeverDisplaysInventedDeployment() {
        let missing = StageModelRouting.availability(environment: [:])
        #expect(!missing.textConfigured)
        #expect(missing.textModelName.isEmpty)
        var values = environment
        values["AZURE_FOUNDRY_MODEL"] = "fixture-explicit-model"
        #expect(StageModelRouting.availability(environment: values).textModelName == "fixture-explicit-model")
        values.removeValue(forKey: "AZURE_API_KEY")
        #expect(StageModelRouting.availability(environment: values).textModelName.isEmpty)
    }
}
