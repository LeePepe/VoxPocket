import Foundation
import Testing
@testable import VoxPocket
import TranscriptionKit

struct TranscriberSelectionTests {
    @MainActor @Test func defaultsSelectCloudFinalAndAzureRefinement() {
        #expect(LLMAppConfig.defaultTranscriberProvider == .hybridWhisper)
        #expect(LLMAppConfig.defaultProvider == .azureFoundry)
        #expect(LLMAppConfig.azureAPIStyle == .openAIV1)
        #expect(LLMAppConfig.azureAuthMode == .apiKey)
    }

    @MainActor @Test func cloudConfigurationUsesDeploymentAndSharedKey() throws {
        let config = try #require(LLMAppConfig.transcriptionConfig(environment: cloudEnvironment))
        #expect(config.endpoint.absoluteString == "https://example.invalid/openai/deployments/fixture-asr/audio/transcriptions?api-version=2024-02-01")
        #expect(config.apiKey == "test-key")
    }

    @MainActor @Test func missingOrUnsafeConfigurationIsRejected() {
        #expect(LLMAppConfig.transcriptionConfig(environment: [:]) == nil)
        for endpoint in ["http://example.invalid", "https://user:password@example.invalid", "not-a-url"] {
            var environment = cloudEnvironment
            environment["AZURE_OPENAI_ENDPOINT"] = endpoint
            #expect(LLMAppConfig.transcriptionConfig(environment: environment) == nil)
        }
    }

    @MainActor @Test func mainAndQuickUseSeparateCloudCoordinatorsWithoutMerger() {
        let main = ServiceContainer.makeTranscriber(environment: cloudEnvironment)
        let quick = ServiceContainer.makeQuickTranscriber(environment: cloudEnvironment)
        #expect(main is HybridWhisperTranscriber)
        #expect(quick is HybridWhisperTranscriber)
        #expect((main as AnyObject) !== (quick as AnyObject))
        #expect((quick as? HybridWhisperTranscriber)?.merger == nil)
    }

    @MainActor @Test func missingCloudConfigurationKeepsRecordingAvailableLocally() {
        #expect(ServiceContainer.makeTranscriber(environment: [:]) is AppleSpeechTranscriber)
    }

    private var cloudEnvironment: [String: String] {
        ["AZURE_OPENAI_ENDPOINT": "https://example.invalid", "AZURE_TRANSCRIPTION_DEPLOYMENT": "fixture-asr", "AZURE_API_KEY": "test-key"]
    }
}
