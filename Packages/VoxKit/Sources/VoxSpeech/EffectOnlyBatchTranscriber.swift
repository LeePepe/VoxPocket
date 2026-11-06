import VoxCore
import Foundation

struct EffectOnlyBatchTranscriber: BatchTranscribing {
    func transcribe(fileURL: URL, language: Locale) async throws -> String {
        throw CancellationError()
    }
}
