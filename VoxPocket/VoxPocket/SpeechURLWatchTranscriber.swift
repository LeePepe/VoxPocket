#if os(iOS)
import Foundation
@preconcurrency import Speech
import Synchronization
import UIKit
import VoxPocketKit
import VoxKitBridge
import VoxRefine

nonisolated struct SpeechURLWatchTranscriber: WatchAudioTranscribing {
    let makeRefinement: @Sendable () -> any RefineWorkflowRunning
    func transcribe(fileURL: URL) async throws -> WatchTranscribedCapture {
        let refinement = makeRefinement()
        guard await authorization() else { throw WatchCaptureError.permissionDenied }
        let raw = try await SpeechURLWatchRecognition().recognize(fileURL)
        try Task.checkCancellation()
        guard refinement.isConfigured else { return WatchTranscribedCapture(rawTranscript: raw) }
        let once = WatchRecognitionOnce<String>()
        let refineTask = Task {
            do { once.finish(.success(try await refinement.refine(RefinementRequest(text: raw)).refinedText)) }
            catch { once.finish(.failure(WatchCaptureError.captureFailed)) }
        }
        let timeout = Task {
            do {
                try await Task.sleep(for: .seconds(20))
                once.finish(.failure(WatchCaptureError.captureFailed)); refinement.cancel(); refineTask.cancel()
            } catch {}
        }
        defer { timeout.cancel(); refineTask.cancel() }
        do {
            let refined = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { once.install($0) }
            } onCancel: { once.finish(.failure(CancellationError())); refinement.cancel(); refineTask.cancel() }
            try Task.checkCancellation()
            return WatchTranscribedCapture(rawTranscript: raw, refinedText: refined)
        } catch {
            try Task.checkCancellation()
            return WatchTranscribedCapture(rawTranscript: raw)
        }
    }
    private func authorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined,
              await MainActor.run(body: { UIApplication.shared.applicationState == .active }) else { return false }
        let once = WatchRecognitionOnce<Bool>()
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(20)); once.finish(.success(false)) } catch {}
        }
        defer { timeout.cancel() }
        return (try? await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.install(continuation)
                SFSpeechRecognizer.requestAuthorization { once.finish(.success($0 == .authorized)) }
            }
        } onCancel: { once.finish(.failure(CancellationError())) }) ?? false
    }
}

// Sendable: Speech 的 callback 与取消由 once gate / Mutex 隔离；系统对象不跨出此边界。
nonisolated private final class SpeechURLWatchRecognition: @unchecked Sendable {
    private struct State {
        var task: SFSpeechRecognitionTask?
        var recognizer: SFSpeechRecognizer?
        var request: SFSpeechURLRecognitionRequest?
        var cancelled = false
    }
    private let state = Mutex(State())
    private let once = WatchRecognitionOnce<String>()
    func recognize(_ url: URL) async throws -> String {
        let timeout = Task { [self] in
            do { try await Task.sleep(for: .seconds(45)); cancel() } catch {}
        }
        defer { timeout.cancel(); cancelTask() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.install(continuation)
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans")),
                      recognizer.isAvailable,
                      recognizer.supportsOnDeviceRecognition else {
                    once.finish(.failure(WatchCaptureError.unavailable)); return
                }
                let request = SFSpeechURLRecognitionRequest(url: url)
                request.requiresOnDeviceRecognition = true
                request.shouldReportPartialResults = false
                let task = recognizer.recognitionTask(with: request) { [once] result, error in
                    if let result, result.isFinal { once.finish(.success(result.bestTranscription.formattedString)) }
                    else if error != nil { once.finish(.failure(WatchCaptureError.captureFailed)) }
                }
                let cancelled = state.withLock { value in
                    value.task = task; value.recognizer = recognizer; value.request = request
                    return value.cancelled
                }
                if cancelled { task.cancel() }
            }
        } onCancel: { [self] in cancel() }
    }
    private func cancel() { once.finish(.failure(CancellationError())); cancelTask() }
    private func cancelTask() {
        let task = state.withLock { value in
            value.cancelled = true; let task = value.task
            value.task = nil; value.recognizer = nil; value.request = nil
            return task
        }
        task?.cancel()
    }
}
#endif
