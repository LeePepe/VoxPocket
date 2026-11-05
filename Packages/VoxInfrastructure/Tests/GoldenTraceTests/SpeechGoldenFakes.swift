import TranscriptionKitCombine
import VoxCore
import AVFoundation
import Combine
import Foundation
import Speech
import Synchronization
@testable import TranscriptionKit

struct GoldenSpeechAuthorization: SpeechAuthorizationProviding {
    let allowed: Bool
    let calls: GoldenEvents
    var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus { allowed ? .authorized : .denied }
    func requestSpeechAuthorization() async -> Bool { calls.append("speech.permission:\(allowed)"); return allowed }
}

/// Combine 桥接；配置不可变，事件由线程安全的 subject 和 Mutex 收集。
final class GoldenAudioSource: AudioBufferSource, @unchecked Sendable {
    private let levels = AsyncValueRelay<Float>(0)
    private let states = AsyncValueRelay<AudioCaptureState>(.idle)
    let permission: Bool
    let calls: GoldenEvents
    let file: URL
    init(permission: Bool = true, calls: GoldenEvents) throws {
        self.permission = permission; self.calls = calls
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoxPocket/TemporaryAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("golden-\(UUID().uuidString).wav")
        try Data().write(to: file)
    }
    func audioLevels() -> AsyncStream<Float> { levels.stream() }
    func captureStates() -> AsyncStream<AudioCaptureState> { states.stream() }
    var state: AudioCaptureState { states.value }
    var hasPermission: Bool { permission }
    func requestPermission() async -> Bool { calls.append("microphone.permission:\(permission)"); return permission }
    func start(bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws {
        calls.append("recorder.start")
        guard await requestPermission() else { throw NSError(domain: "GoldenMicrophone", code: -1) }
        states.send(.recording)
    }
    func startIfAllowed(shouldStart: @escaping @Sendable () -> Bool, bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws {
        guard shouldStart() else { throw CancellationError() }
        try await start(bufferHandler: bufferHandler)
    }
    func level(_ value: Float) { levels.send(value) }
    func pause() { calls.append("recorder.pause"); states.send(.paused) }
    func resume() { calls.append("recorder.resume"); states.send(.recording) }
    func stop() -> URL? { calls.append("recorder.stop"); states.send(.idle); return file }
}

final class GoldenRecognizer: SpeechRecognizing, Sendable {
    private let handler = Mutex<(@Sendable (RecognitionUpdate) -> Void)?>(nil)
    let calls: GoldenEvents
    let isAvailable: Bool
    let startupFails: Bool
    init(calls: GoldenEvents, available: Bool = true, startupFails: Bool = false) {
        self.calls = calls; isAvailable = available; self.startupFails = startupFails
    }
    func isAvailable(for locale: Locale) -> Bool { calls.append("speech.available:\(locale.identifier)"); return isAvailable }
    func recognitionTask(locale: Locale, request: SFSpeechAudioBufferRecognitionRequest,
                         handler: @escaping @Sendable (RecognitionUpdate) -> Void) throws -> any SpeechRecognitionTasking {
        calls.append("speech.start:\(locale.identifier)")
        if startupFails { throw NSError(domain: "GoldenRecognizer", code: -7) }
        self.handler.withLock { $0 = handler }
        return GoldenRecognitionTask(calls: calls)
    }
    func emit(_ text: String, final: Bool = false) {
        handler.withLock { $0 }?(.init(text: text, isFinal: final, confidence: final ? 0 : nil))
    }
}

private final class GoldenRecognitionTask: SpeechRecognitionTasking, Sendable {
    let calls: GoldenEvents
    init(calls: GoldenEvents) { self.calls = calls }
    func finish() { calls.append("speech.finish") }
    func cancel() { calls.append("speech.cancel") }
}

struct GoldenBatch: BatchTranscribing {
    let calls: GoldenEvents
    func transcribe(fileURL: URL, language: Locale) async throws -> String {
        calls.append("batch.transcribe:\(language.identifier)")
        return "synthetic batch"
    }
}

final class GoldenRealtime: RealtimePipelining, RealtimeSessionMaking, Sendable {
    private struct Callbacks: Sendable {
        var partial: (@Sendable (String) -> Void)?
        var fallback: (@Sendable () -> Void)?
    }
    private let callbacks = Mutex(Callbacks())
    let calls: GoldenEvents
    let hasMinimumAudio: Bool
    let fails: Bool
    init(calls: GoldenEvents, minimumAudio: Bool = true, fails: Bool = false) {
        self.calls = calls; hasMinimumAudio = minimumAudio; self.fails = fails
    }
    func makePipeline(config: AzureRealtimeTranscriptionConfig, onPartial: @escaping @Sendable (String) -> Void,
                      onFallback: @escaping @Sendable () -> Void) -> any RealtimePipelining {
        calls.append("realtime.make")
        callbacks.withLock { $0 = .init(partial: onPartial, fallback: onFallback) }
        return self
    }
    func start(language: Locale) async { calls.append("realtime.start:\(language.identifier)") }
    func append(_ buffer: AVAudioPCMBuffer) { calls.append("realtime.append") }
    func partial() { callbacks.withLock { $0.partial }?("synthetic cloud partial") }
    func fallback() { calls.append("realtime.fallback"); callbacks.withLock { $0.fallback }?() }
    func finish() async throws -> String {
        calls.append("realtime.finish")
        if fails { throw RealtimeTranscriptionError.connectionFailed }
        return "synthetic cloud final"
    }
    func cancel() async { calls.append("realtime.cancel") }
    func cancelQuickRecording() async { calls.append("realtime.cancelQuickRecording") }
}

struct GoldenMerger: TranscriptionMerger {
    let calls: GoldenEvents
    func merge(appleSpeech: String, whisper: String) async throws -> String {
        calls.append("merge:\(appleSpeech)|\(whisper)")
        return "synthetic merged"
    }
}

struct GoldenLocalEngine: LocalWhisperEngine {
    let calls: GoldenEvents
    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {}
    func startStreaming(languageCode: String?, onPartial: @escaping @Sendable (String) -> Void,
                        onAudioLevel: @escaping @Sendable (Float) -> Void) async throws {}
    func stopStreaming() async {}
    func pauseStreaming() async {}
    func resumeStreaming() async {}
    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? { nil }
    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? {
        calls.append("local.transcribe:\(languageCode ?? "nil")")
        return "synthetic local"
    }
}

final class GoldenSpeechProbe {
    private let events = GoldenEvents()
    private var subscriptions: [AnyCancellable] = []
    var values: [String] { events.values }
    func waitFor(_ event: String, count: Int = 1) async {
        await assertEventually { self.values.filter { $0 == event }.count >= count }
    }
    init(_ coordinator: any TranscriptionCoordinator) {
        subscriptions.append(coordinator.liveResultPublisher.sink(receiveCompletion: { _ in }, receiveValue: { [events] result in
            let confidence = result.confidence.map { String($0) } ?? "nil"
            events.append("live:\(result.type.rawValue):\(result.text):\(confidence)")
        }))
        subscriptions.append(coordinator.finalResultPublisher.sink(receiveCompletion: { _ in }, receiveValue: { [events] result in
            events.append("final:\(result.text)")
        }))
        subscriptions.append(coordinator.audioLevelPublisher.sink { [events] in events.append("level:\($0)") })
        subscriptions.append(coordinator.audioCaptureService.statePublisher.sink { [events] in events.append("state:\($0)") })
    }
}
