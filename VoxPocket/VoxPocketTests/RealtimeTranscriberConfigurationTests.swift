import VoxCore
import Foundation
import Testing
import Preferences
import VoxLLM
import VoxSpeech
import VoxKitBridge
import VoxWorkflow
@testable import VoxPocket

struct RealtimeTranscriberConfigurationTests {
    private func deployment(_ config: AzureRealtimeTranscriptionConfig) -> String? {
        Mirror(reflecting: config).children.first(where: { $0.label == "deployment" })?.value as? String
    }

    private var environment: [String: String] {
        ["AZURE_OPENAI_ENDPOINT": "https://example.invalid", "AZURE_API_KEY": "fixture-key"]
    }

    @MainActor @Test func textAvailabilityUsesStrictEndpointValidation() {
        var values = environment
        values["AZURE_FOUNDRY_ENDPOINT"] = "https://example.invalid"
        #expect(StageModelRouting.availability(environment: values).textConfigured)
        values["AZURE_FOUNDRY_ENDPOINT"] = "https://example.invalid#fragment"
        #expect(!StageModelRouting.availability(environment: values).textConfigured)
    }

    @MainActor @Test func realtimeIsOptInAndMacOSOnly() {
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: environment) == nil)
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: environment, deploymentOverride: "fixture-live-override") != nil)
        var values = environment
        values["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "fixture-live"
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values) != nil)
    }

    @MainActor @Test func selectedRealtimeStreamModelRoutesToItsDeployment() {
        var values = environment
        values["AZURE_GPT_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "fixture-gpt"
        values["AZURE_MAI_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "fixture-mai"
        let gpt = StageModelSettings(realtimeStreamModel: .gptRealtime)
        let mai = StageModelSettings(realtimeStreamModel: .maiTranscribe2)
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values, settings: gpt).map(deployment) == "fixture-gpt")
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values, settings: mai).map(deployment) == "fixture-mai")
        values.removeValue(forKey: "AZURE_GPT_REALTIME_TRANSCRIPTION_DEPLOYMENT")
        values.removeValue(forKey: "AZURE_MAI_REALTIME_TRANSCRIPTION_DEPLOYMENT")
        values["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "fixture-legacy"
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: values, settings: mai).map(deployment) == "fixture-legacy")
        #expect(StageModelRouting.availability(environment: [
            "AZURE_OPENAI_ENDPOINT": "https://example.invalid",
            "AZURE_API_KEY": "fixture-key",
            "AZURE_GPT_REALTIME_TRANSCRIPTION_DEPLOYMENT": "fixture-gpt",
            "AZURE_MAI_REALTIME_TRANSCRIPTION_DEPLOYMENT": "fixture-mai"
        ]).gptRealtimeDeployment == "fixture-gpt")
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
        let availability = StageModelRouting.availability(environment: values)
        #expect(StagePresetMapping.preset(settings: .init(), batchConfigured: availability.batchConfigured,
            realtimeConfigured: availability.realtimeCredentialsConfigured, azureTextConfigured: availability.textConfigured)
            .exportedPipeline().realtime == availability.realtimeCredentialsConfigured)
        #expect(StagePresetMapping.preset(settings: .init(speech: .batch), batchConfigured: true,
            realtimeConfigured: true, azureTextConfigured: true).exportedPipeline().realtime == false)
        #expect(StagePresetMapping.preset(settings: .init(speech: .appleSpeech), batchConfigured: true,
            realtimeConfigured: true, azureTextConfigured: true).exportedPipeline().speech == ["capture.microphone", "speech.apple"])
        #expect(StageModelRouting.availability(environment: [:]).batchConfigured == false)
    }

    @MainActor @Test func settingsDeploymentEnablesLegacyConfigurationWithoutChangingKeys() {
        let settings = StageModelSettings(realtimeDeployment: "fixture-live-override")
        let availability = StageModelRouting.availability(environment: environment)
        #expect(availability.batchConfigured)
        #expect(availability.realtimeCredentialsConfigured)
        #expect(LLMAppConfig.realtimeTranscriptionConfig(environment: environment, deploymentOverride: settings.realtimeDeployment) != nil)
        #expect(availability.realtimeDeployment.isEmpty)
        #expect(availability.textModelName == "默认文本模型")
    }

    @MainActor @Test func analysisRoutingUsesIndependentIntentAndToneSelections() {
        let settings = StageModelSettings(intent: .azureFoundry, tone: .appleIntelligence, refinement: .azureFoundry)
        let preset = StagePresetMapping.preset(settings: settings, batchConfigured: true,
            realtimeConfigured: true, azureTextConfigured: true)
        let pipeline = preset.exportedPipeline()
        #expect(pipeline.analysis["intent"] == "azureFoundry")
        #expect(pipeline.analysis["entities"] == "azureFoundry")
        #expect(pipeline.analysis["tone"] == "appleIntelligence")
    }

    @MainActor @Test func unavailableTextConfigurationDoesNotBlockSpeechSetupOrUseWrongTextModel() async {
        let speech = StageModelRouting.prepareSession(settings: .init(), environment: [:], beforeSession: nil)
        #expect(speech is AppleSpeechTranscriber)
        let preset = StagePresetMapping.preset(settings: .init(), batchConfigured: false,
            realtimeConfigured: false, azureTextConfigured: false)
        let runner = RefineWorkflowRunner(preset: preset,
            configuration: WorkflowExecutionConfiguration(), azureTextConfigured: false)
        do {
            _ = try await runner.refine(.init(text: "synthetic input"))
            Issue.record("Unconfigured selected cloud model must not silently use Apple")
        } catch RefineWorkflowConfigurationError.unavailable {
        } catch {
            Issue.record("Unexpected configuration error: \(error)")
        }
    }

    @MainActor @Test func recordingChannelsOwnDifferentTextSnapshots() throws {
        let config = LLMProviderConfig(providerType: .azureFoundry, apiKey: Credential(rawValue: "fixture-key"),
                                       baseURL: URL(string: "https://example.invalid"), modelIdentifier: "fixture-text")
        let configuration = WorkflowExecutionConfiguration(azureFoundryConfig: config)
        let main = RefineWorkflowRunner(preset: .default, configuration: configuration, azureTextConfigured: true)
        let quick = RefineWorkflowRunner(preset: .default, configuration: configuration, azureTextConfigured: true)
        #expect(ObjectIdentifier(main) != ObjectIdentifier(quick))
        #expect(main.currentProviderType == .azureFoundry)
        quick.configure(preset: .appleSpeech, configuration: configuration, azureTextConfigured: true)
        #expect(main.currentProviderType == .azureFoundry)
        #expect(quick.currentProviderType == .appleIntelligence)
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

    @MainActor @Test func stageSpeechSessionFactoryReusesSourceWhenSettingsUnchangedAndReplacesWhenChanged() async throws {
        let suiteName = "StageSpeechSessionFactoryTests.\(UUID())"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suiteName)!)
        await store.setValue("appleSpeech", for: .speechModel)

        var seenSettings: [StageModelSettings] = []
        let sdk = SDKHostConfiguration(
            storageLocations: SDKHostConfiguration.storageLocations(),
            logger: NoopVoxLogger(),
            telemetry: NoopVoxTelemetry(),
            credentials: SDKHostConfiguration.credentials(environment: environment)
        )
        let factory = StageSpeechSessionFactory(
            environment: environment,
            preferences: store,
            sdk: sdk,
            beforeSession: { seenSettings.append($0) }
        )

        let first = try await factory.makeSource()
        let second = try await factory.makeSource()
        #expect(ObjectIdentifier(first as AnyObject) == ObjectIdentifier(second as AnyObject))
        #expect(seenSettings.count == 2)
        #expect(seenSettings.allSatisfy { $0.speech == .appleSpeech })

        await store.setValue("batch", for: .speechModel)
        let third = try await factory.makeSource()
        #expect(ObjectIdentifier(third as AnyObject) != ObjectIdentifier(first as AnyObject))
        #expect(seenSettings.count == 3)
        #expect(seenSettings.last?.speech == .batch)

        await store.setValue("realtime", for: .speechModel)
        await store.setValue("maiTranscribe2", for: .realtimeStreamModel)
        let fourth = try await factory.makeSource()
        #expect(ObjectIdentifier(fourth as AnyObject) != ObjectIdentifier(third as AnyObject))
        #expect(seenSettings.count == 4)
        #expect(seenSettings.last?.realtimeStreamModel == .maiTranscribe2)
    }
}
import VoxRefine
