import VoxCore
import AVFoundation
import Foundation
import Speech

package protocol SpeechAuthorizationProviding: Sendable {
    func requestSpeechAuthorization() async -> Bool
    var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }
}

package struct SystemSpeechAuthorizationProvider: SpeechAuthorizationProviding, Sendable {
    package init() {}
    package func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    package var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
}

package protocol MicrophoneAuthorizationProviding: Sendable {
    func requestMicrophoneAccess() async -> Bool
    var hasMicrophoneAccess: Bool { get }
}

package struct SystemMicrophoneAuthorizationProvider: MicrophoneAuthorizationProviding, Sendable {
    package func requestMicrophoneAccess() async -> Bool {
        #if os(iOS)
        await AVAudioApplication.requestRecordPermission()
        #else
        await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    package var hasMicrophoneAccess: Bool {
        #if os(iOS)
        AVAudioApplication.shared.recordPermission == .granted
        #else
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif
    }
}

package protocol AudioBufferSource: AnyObject, Sendable {
    func audioLevels() -> AsyncStream<Float>
    func captureStates() -> AsyncStream<AudioCaptureState>
    var state: AudioCaptureState { get }
    func requestPermission() async -> Bool
    var hasPermission: Bool { get }
    func start(bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws
    func startIfAllowed(shouldStart: @escaping @Sendable () -> Bool, bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws
    func pause()
    func resume()
    func stop() -> URL?
}

package struct RecognitionUpdate: Sendable {
    package let text: String?
    package let isFinal: Bool
    package let confidence: Float?
    package let error: (any Error)?

    package init(text: String?, isFinal: Bool, confidence: Float? = nil, error: (any Error)? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.error = error
    }
}

package protocol SpeechRecognitionTasking: AnyObject, Sendable {
    func finish()
    func cancel()
}

package protocol SpeechRecognizing: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func isAvailable(for locale: Locale) -> Bool
    func recognitionTask(locale: Locale, request: SFSpeechAudioBufferRecognitionRequest,
                        handler: @escaping @Sendable (RecognitionUpdate) -> Void) throws -> any SpeechRecognitionTasking
}

package final class SystemSpeechRecognitionTask: SpeechRecognitionTasking, @unchecked Sendable { // Sendable: Apple Speech task finish/cancel are thread-safe.
    private let task: SFSpeechRecognitionTask
    package init(_ task: SFSpeechRecognitionTask) { self.task = task }
    package func finish() { task.finish() }
    package func cancel() { task.cancel() }
}

package final class SystemSpeechRecognizer: SpeechRecognizing, @unchecked Sendable { // Sendable: immutable Apple recognizer is used only via framework callbacks.
    private let recognizer: SFSpeechRecognizer?
    package init(locale: Locale) { recognizer = SFSpeechRecognizer(locale: locale) }
    package var isAvailable: Bool { recognizer?.isAvailable ?? false }
    package func isAvailable(for locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
    }

    package func recognitionTask(locale: Locale, request: SFSpeechAudioBufferRecognitionRequest,
                                 handler: @escaping @Sendable (RecognitionUpdate) -> Void) throws -> any SpeechRecognitionTasking {
        let recognizer = recognizer?.locale.identifier == locale.identifier ? recognizer : SFSpeechRecognizer(locale: locale)
        guard let recognizer else { throw NSError(domain: "SpeechRecognizer", code: -1) }
        let task = recognizer.recognitionTask(with: request) { result, error in
            let update = RecognitionUpdate(
                text: result?.bestTranscription.formattedString,
                isFinal: result?.isFinal ?? false,
                confidence: result?.isFinal == true ? (result?.bestTranscription.segments.last?.confidence ?? 0) : nil,
                error: error
            )
            handler(update)
        }
        return SystemSpeechRecognitionTask(task)
    }
}

package protocol BatchTranscribing: Sendable {
    func transcribe(fileURL: URL, language: Locale) async throws -> String
}

extension WhisperEngine: BatchTranscribing {}

package protocol RealtimePipelining: Sendable {
    var hasMinimumAudio: Bool { get }
    func start(language: Locale) async
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> String
    func cancel() async
    func cancelQuickRecording() async
}

struct RealtimePipelineAdapter: RealtimePipelining, Sendable {
    let pipeline: RealtimeAudioPipeline
    let session: DefaultRealtimeTranscriptionSession?

    init(pipeline: RealtimeAudioPipeline, session: DefaultRealtimeTranscriptionSession? = nil) {
        self.pipeline = pipeline
        self.session = session
    }

    var hasMinimumAudio: Bool { pipeline.hasMinimumAudio }

    func start(language: Locale) async {
        pipeline.start(language: language.language.languageCode?.identifier ?? "zh")
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        pipeline.append(buffer)
    }

    func finish() async throws -> String {
        try await pipeline.finish()
    }

    func cancel() async {
        pipeline.cancel()
    }

    func cancelQuickRecording() async {
        if let session { await cancelQuickRecordingRealtime(pipeline, session: session) }
        else { pipeline.cancel() }
    }
}

package protocol RealtimeSessionMaking: Sendable {
    func makePipeline(config: AzureRealtimeTranscriptionConfig,
                      onPartial: @escaping @Sendable (String) -> Void,
                      onFallback: @escaping @Sendable () -> Void) -> any RealtimePipelining
}

package struct DefaultRealtimeSessionMaker: RealtimeSessionMaking, Sendable {
    package init() {}
    package func makePipeline(config: AzureRealtimeTranscriptionConfig,
                              onPartial: @escaping @Sendable (String) -> Void,
                              onFallback: @escaping @Sendable () -> Void) -> any RealtimePipelining {
        let session = DefaultRealtimeTranscriptionSession(config: config, onPartial: onPartial)
        return RealtimePipelineAdapter(pipeline: RealtimeAudioPipeline(session: session, onFailure: onFallback), session: session)
    }
}
