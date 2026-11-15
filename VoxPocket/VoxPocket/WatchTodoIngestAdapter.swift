import Foundation
import CoreModels
import UseCases
import VoxPocketKit

/// 应用壳只把 Watch 入库请求串行转发给 VoxApplication 的 VoiceCaptureAndTodoUseCase。
actor WatchTodoIngestAdapter {
    private let useCase: any VoiceCaptureAndTodoUseCase
    private var tail: Task<WatchTodoResult, Error>?
    init(useCase: any VoiceCaptureAndTodoUseCase) {
        self.useCase = useCase
    }
    func ingest(captureID: UUID, transcript: WatchTranscribedCapture, metadata: WatchCaptureMetadata) async throws -> WatchTodoResult {
        guard captureID == metadata.captureID else { throw WatchCaptureError.invalidAudioFile }
        let previous = tail
        let operation = Task { [useCase] in
            _ = await previous?.result
            try Task.checkCancellation()
            do {
                let todo = try await useCase.reconcileWatchTodoCapture(
                    rawTranscript: transcript.rawTranscript,
                    refinedText: transcript.refinedText,
                    localAudioFileName: metadata.basename,
                    durationSeconds: metadata.duration
                )
                return WatchTodoResult(title: todo.title, todoID: todo.id)
            } catch {
                throw WatchCaptureError.captureFailed
            }
        }
        tail = operation
        return try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
    }
}
