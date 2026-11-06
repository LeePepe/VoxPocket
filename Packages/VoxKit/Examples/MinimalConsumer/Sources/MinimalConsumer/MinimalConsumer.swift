import Foundation
import VoxCore
import VoxLLM
import VoxRefine
import VoxSpeech

@main
struct MinimalConsumer {
    static func main() async {
        let logger = NoopVoxLogger()
        let storage = VoxStorageLocations(
            temporaryAudio: URL(fileURLWithPath: "/example-audio", isDirectory: true),
            modelCache: URL(fileURLWithPath: "/example-models", isDirectory: true))
        let speech: any SpeechSessionSource = AppleSpeechTranscriber(logger: logger, storageLocations: storage)
        let provider: any LLMProvider = AppleIntelligenceProvider(logger: logger)
        let request = RefinementRequest(text: "synthetic example")
        _ = (speech.supportedLanguages, provider.isAvailable, request)
    }
}
