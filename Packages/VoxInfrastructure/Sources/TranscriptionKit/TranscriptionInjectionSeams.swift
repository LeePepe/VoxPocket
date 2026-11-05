import AVFoundation
import Combine
import Foundation
import Speech

protocol SpeechAuthorizationProviding: Sendable {
    func requestSpeechAuthorization() async -> Bool
    var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }
}

struct SystemSpeechAuthorizationProvider: SpeechAuthorizationProviding, Sendable {
    func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
}

protocol MicrophoneAuthorizationProviding: Sendable {
    func requestMicrophoneAccess() async -> Bool
    var hasMicrophoneAccess: Bool { get }
}

struct SystemMicrophoneAuthorizationProvider: MicrophoneAuthorizationProviding, Sendable {
    func requestMicrophoneAccess() async -> Bool {
        #if os(iOS)
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        #else
        await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    var hasMicrophoneAccess: Bool {
        #if os(iOS)
        AVAudioSession.sharedInstance().recordPermission == .granted
        #else
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif
    }
}

protocol AudioBufferSource: AnyObject, Sendable {
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
    var statePublisher: AnyPublisher<AudioCaptureState, Never> { get }
    var state: AudioCaptureState { get }
    func requestPermission() async -> Bool
    var hasPermission: Bool { get }
    func start(bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws
    func startIfAllowed(shouldStart: @escaping @Sendable () -> Bool, bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws
    func pause()
    func resume()
    func stop() -> URL?
}

struct RecognitionUpdate: Sendable {
    let text: String?
    let isFinal: Bool
    let confidence: Float?
    let error: (any Error)?

    init(text: String?, isFinal: Bool, confidence: Float? = nil, error: (any Error)? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.error = error
    }
}

protocol SpeechRecognitionTasking: AnyObject, Sendable {
    func finish()
    func cancel()
}

protocol SpeechRecognizing: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func isAvailable(for locale: Locale) -> Bool
    func recognitionTask(locale: Locale, request: SFSpeechAudioBufferRecognitionRequest,
                         handler: @escaping @Sendable (RecognitionUpdate) -> Void) throws -> any SpeechRecognitionTasking
}

final class SystemSpeechRecognitionTask: SpeechRecognitionTasking, @unchecked Sendable {
    private let task: SFSpeechRecognitionTask
    init(_ task: SFSpeechRecognitionTask) { self.task = task }
    func finish() { task.finish() }
    func cancel() { task.cancel() }
}

final class SystemSpeechRecognizer: SpeechRecognizing, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer?
    init(locale: Locale) { recognizer = SFSpeechRecognizer(locale: locale) }
    var isAvailable: Bool { recognizer?.isAvailable ?? false }
    func isAvailable(for locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
    }

    func recognitionTask(locale: Locale, request: SFSpeechAudioBufferRecognitionRequest,
                         handler: @escaping @Sendable (RecognitionUpdate) -> Void) throws -> any SpeechRecognitionTasking {
        let recognizer = recognizer?.locale.identifier == locale.identifier ? recognizer : SFSpeechRecognizer(locale: locale)
        guard let recognizer else { throw NSError(domain: "SpeechRecognizer", code: -1) }
        let task = recognizer.recognitionTask(with: request) { result, error in
            let update = RecognitionUpdate(
                text: result?.bestTranscription.formattedString,
                isFinal: result?.isFinal ?? false,
                confidence: result?.isFinal == true ? result?.bestTranscription.segments.last?.confidence : nil,
                error: error
            )
            handler(update)
        }
        return SystemSpeechRecognitionTask(task)
    }
}

protocol BatchTranscribing: Sendable {
    func transcribe(fileURL: URL, language: Locale) async throws -> String
}

extension WhisperEngine: BatchTranscribing {}

protocol RealtimePipelining: Sendable {
    var hasMinimumAudio: Bool { get }
    func start(language: Locale) async
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> String
    func cancel() async
}

struct RealtimePipelineAdapter: RealtimePipelining, Sendable {
    let pipeline: RealtimeAudioPipeline

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
}

protocol RealtimeSessionMaking: Sendable {
    func makePipeline(config: AzureRealtimeTranscriptionConfig,
                      onPartial: @escaping @Sendable (String) -> Void) -> any RealtimePipelining
}

struct DefaultRealtimeSessionMaker: RealtimeSessionMaking, Sendable {
    func makePipeline(config: AzureRealtimeTranscriptionConfig,
                      onPartial: @escaping @Sendable (String) -> Void) -> any RealtimePipelining {
        let session = DefaultRealtimeTranscriptionSession(config: config, onPartial: onPartial)
        return RealtimePipelineAdapter(pipeline: RealtimeAudioPipeline(session: session))
    }
}
