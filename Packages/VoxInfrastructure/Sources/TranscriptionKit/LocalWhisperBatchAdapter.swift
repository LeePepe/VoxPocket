import Foundation

struct LocalWhisperBatchAdapter: BatchTranscribing, Sendable {
    let engine: any LocalWhisperEngine

    func transcribe(fileURL: URL, language: Locale) async throws -> String {
        try await engine.transcribeAudioFile(atPath: fileURL.path, languageCode: language.language.languageCode?.identifier)
            ?? ""
    }
}
