import Foundation
import Testing
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
}
