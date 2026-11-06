import VoxCore
import Foundation
import VoxSpeech

struct LocalWhisperBatchAdapter: BatchTranscribing, Sendable {
    let engine: any LocalWhisperEngine
    let config: LocalWhisperKitConfig

    func transcribe(fileURL: URL, language: Locale) async throws -> String {
        let languageCode = config.languageHint(for: language)
        return try await engine.transcribeAudioFile(atPath: fileURL.path, languageCode: languageCode)
            ?? ""
    }
}
