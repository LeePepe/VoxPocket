import Foundation
import Testing
@testable import VoxPocket
import TranscriptionKit
import Preferences

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

    @MainActor @Test func privateFileFeedsExistingCloudConfigurationMapper() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.json")
        let data = Data(#"{"azure":{"endpoint":"https://example.invalid","apiKey":"test-key","transcriptionDeployment":"private-asr","refinementDeployment":"private-llm"}}"#.utf8)
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let runtime = try await DefaultPrivateModelConfigurationLoader(fileURL: url).load(environment: [:])
        let config = try #require(LLMAppConfig.transcriptionConfig(environment: runtime.environmentValues))
        #expect(config.endpoint.path.contains("/deployments/private-asr/"))
        #expect(config.apiKey == "test-key")
        #expect(LLMAppConfig.refinementAPIKey(environment: runtime.environmentValues) == "test-key")
        #expect(runtime.environmentValues["AZURE_FOUNDRY_MODEL"] == "private-llm")
    }

    @MainActor @Test func missingOrUnsafeConfigurationIsRejected() {
        #expect(LLMAppConfig.transcriptionConfig(environment: [:]) == nil)
        for endpoint in ["http://example.invalid", "https://user:password@example.invalid", "not-a-url"] {
            var environment = cloudEnvironment
            environment["AZURE_OPENAI_ENDPOINT"] = endpoint
            #expect(LLMAppConfig.transcriptionConfig(environment: environment) == nil)
        }
    }

    @MainActor @Test func sharedKeyWinsAndEmptyValuesDoNotMaskLegacyKeys() {
        var environment = cloudEnvironment
        environment["kimikey"] = "old-text-key"
        environment["whisperkey"] = "old-audio-key"
        #expect(LLMAppConfig.refinementAPIKey(environment: environment) == "test-key")
        #expect(LLMAppConfig.transcriptionConfig(environment: environment)?.apiKey == "test-key")
        environment["AZURE_API_KEY"] = "  "
        #expect(LLMAppConfig.refinementAPIKey(environment: environment) == "old-text-key")
        #expect(LLMAppConfig.transcriptionConfig(environment: environment)?.apiKey == "old-audio-key")
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
