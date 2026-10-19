import AVFoundation
import Combine
import Foundation
import LokiKit
import Speech
import Synchronization

/// Apple Speech Framework 转录协调器
///
/// 使用 `MicrophoneRecorder` 采集音频，`SFSpeechRecognizer` 实时识别文字。
/// Combine 桥接沿用 unchecked Sendable；会话资格及身份由 Mutex 生命周期保护。
public final class AppleSpeechTranscriber: NSObject, @unchecked Sendable {

    // MARK: - Dependencies

    fileprivate let recorder: MicrophoneRecorder
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Publishers

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    // MARK: - State

    private let recording = HybridRecordingLifecycle()
    private let sessionEffects: QuickRecordingSessionEffects?
    private let logger: Logger

    // MARK: - Sub-services

    private lazy var _audioCaptureService: AppleAudioCapture = AppleAudioCapture(transcriber: self)
    private lazy var _speechRecognitionService: AppleSpeechRecognition = AppleSpeechRecognition(transcriber: self)

    // MARK: - Init

    public override init() {
        self.recorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "AppleSpeechTranscriber.Mic"))
        self.logger = PrintLogger(subsystem: "AppleSpeechTranscriber")
        self.sessionEffects = nil
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        logger.debug("init with default locale zh-Hans")
    }

    public init(locale: Locale, logger: Logger = PrintLogger(subsystem: "AppleSpeechTranscriber")) {
        self.recorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "AppleSpeechTranscriber.Mic"))
        self.logger = logger
        self.sessionEffects = nil
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        logger.debug("init with locale: \(locale.identifier)")
    }

    init(effects: QuickRecordingSessionEffects) {
        recorder = MicrophoneRecorder()
        logger = PrintLogger(subsystem: "AppleSpeechTranscriber")
        sessionEffects = effects
        super.init()
    }
}

// MARK: - TranscriptionCoordinator

extension AppleSpeechTranscriber: TranscriptionCoordinator {

    public var audioCaptureService: AudioCaptureService { _audioCaptureService }
    public var speechRecognitionService: SpeechRecognitionService { _speechRecognitionService }

    public var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        finalResultSubject.eraseToAnyPublisher()
    }

    public var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        liveResultSubject.eraseToAnyPublisher()
    }

    public var audioLevelPublisher: AnyPublisher<Float, Never> {
        recorder.audioLevelPublisher
    }

    public var isTranscribing: Bool {
        recording.isRecording
    }

    public func start(language: Locale) async throws {
        logger.info("start() language: \(language.identifier)")

        if recording.isRecording {
            logger.warning("Already transcribing, stopping first")
            await stop()
        }
        let id = try recording.begin(locale: language)
        do {
            if let sessionEffects {
                try await sessionEffects.start(id, language) { [weak self] result in
                    self?.receiveAppleResult(result, id: id)
                }
                try recording.didStart(id)
                captureStateSubject.send(.recording)
            } else {
                try await startRecording(language: language, id: id)
            }
        } catch {
            try? await discardRecording(id)
            recording.complete(id)
            throw error
        }
    }

    private func startRecording(language: Locale, id: UUID) async throws {
        try await authorizeSpeech()
        try Task.checkCancellation()
        guard recording.isStarting(id) else { throw CancellationError() }
        let recognizer = try recognizer(language: language)
        recognitionTask?.finish()
        recognitionTask = nil
        let request = DefaultAppleSpeechRequestFactory.makeRequest()
        recognitionRequest = request
        try await recorder.startIfAllowed(shouldStart: { [recording] in recording.isStarting(id) }) { buffer in
            request.append(buffer)
        }
        try Task.checkCancellation()
        startAppleTask(recognizer, request: request, language: language, id: id)
        try recording.didStart(id)
        captureStateSubject.send(.recording)
        logger.info("Recording + recognition started")
    }

    private func authorizeSpeech() async throws {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else {
            throw NSError(domain: "AppleSpeechTranscriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "语音识别权限未授权"])
        }

    }

    private func recognizer(language: Locale) throws -> SFSpeechRecognizer {
        if speechRecognizer?.locale.language.languageCode != language.language.languageCode {
            speechRecognizer = SFSpeechRecognizer(locale: language)
        }
        guard let speechRecognizer else {
            throw NSError(domain: "AppleSpeechTranscriber", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer 不可用"])
        }

        return speechRecognizer
    }

    private func startAppleTask(_ recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
                                language: Locale, id: UUID) {
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.recording.acceptsAppleResult(id) else { return }

            if let result {
                let transcriptionResult = TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    type: result.isFinal ? .final : .partial,
                    confidence: result.isFinal
                        ? Double(result.bestTranscription.segments.last?.confidence ?? 0)
                        : nil,
                    timestamp: Date(),
                    locale: language
                )
                self.receiveAppleResult(transcriptionResult, id: id)
                if result.isFinal { self.recognitionTask = nil }
            }

            if let error {
                let e = error as NSError
                // code 301 (kLSRErrorDomain) 是 endAudio 后的正常取消信号
                if e.code == 301 || e.code == NSURLErrorCancelled {
                    self.logger.debug("Recognition task ended (expected on stop)")
                } else {
                    self.logger.error("Recognition error: \(e.domain) \(e.code) \(e.localizedDescription)")
                }
                self.recognitionTask = nil
            }
        }
    }

    private func receiveAppleResult(_ result: TranscriptionResult, id: UUID) {
        _ = recording.receiveApple(result.text, id: id, retainText: false)
        guard recording.acceptsAppleResult(id) else { return }
        liveResultSubject.send(result)
        if result.isFinal { finalResultSubject.send(result) }
    }

    public func stop() async {
        switch recording.requestStop() {
        case .none: return
        case .cancelStart(let session): await recording.waitForCleanup(session.id)
        case .finish(let session): await finishRecording(session.id)
        case .discard(let session):
            try? await discardRecording(session.id)
            recording.complete(session.id)
        }
    }

    private func finishRecording(_ id: UUID) async {
        let file = await stopCapture(discard: false)
        try? await removeAudio(file)
        recording.complete(id, keepResults: true)
    }

    private func discardRecording(_ id: UUID) async throws {
        let file = await stopCapture(discard: true)
        try await removeAudio(file)
    }

    private func stopCapture(discard: Bool) async -> URL? {
        let file: URL?
        if let sessionEffects {
            file = await sessionEffects.stopCapture()
            if discard { sessionEffects.cancelApple() }
            else { sessionEffects.endAppleAudio() }
        } else {
            file = await MainActor.run {
                let file = self.recorder.stop()
                if discard { self.recognitionTask?.cancel(); self.recognitionTask = nil }
                else { self.recognitionRequest?.endAudio() }
                self.recognitionRequest = nil
                return file
            }
        }
        captureStateSubject.send(.idle)
        return file
    }

    private func removeAudio(_ file: URL?) async throws {
        if let sessionEffects { try await sessionEffects.removeAudio(file); return }
        guard let file else { return }
        await Task.detached { try? FileManager.default.removeItem(at: file) }.value
    }

    public func pause() {
        recorder.pause()
        captureStateSubject.send(.paused)
    }

    public func resume() {
        recorder.resume()
        captureStateSubject.send(.recording)
    }

}

extension AppleSpeechTranscriber: QuickRecordingReleaseControlling {
    public func prepareQuickRecording() throws { try recording.prepareQuickRecording() }

    public func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        try recording.freezeQuickRecordingRelease()
    }

    public func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        if snapshot.hasRecognizedSpeech { await recording.waitForStartup(snapshot.sessionID) }
        switch recording.claimQuickRelease(snapshot) {
        case .none: return
        case .cancelStart(let session): await recording.waitForCleanup(session.id)
        case .finish(let session): await finishRecording(session.id)
        case .discard(let session):
            defer { recording.complete(session.id) }
            try await discardRecording(session.id)
        }
    }
}

// MARK: - Internal AudioCaptureService

private final class AppleAudioCapture: AudioCaptureService, @unchecked Sendable {
    private weak var transcriber: AppleSpeechTranscriber?
    init(transcriber: AppleSpeechTranscriber) { self.transcriber = transcriber }

    var state: AudioCaptureState { transcriber?.captureStateSubject.value ?? .idle }

    var statePublisher: AnyPublisher<AudioCaptureState, Never> {
        transcriber?.captureStateSubject.eraseToAnyPublisher() ?? Just(.idle).eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        transcriber?.audioLevelPublisher ?? Just(0).eraseToAnyPublisher()
    }

    func startCapture() async throws {}
    func stopCapture() async {}
    func pauseCapture() { transcriber?.pause() }
    func resumeCapture() { transcriber?.resume() }

    func requestPermission() async -> Bool {
        await transcriber?.recorder.requestPermission() ?? false
    }

    var hasPermission: Bool { transcriber?.recorder.hasPermission ?? false }
}

// MARK: - Internal SpeechRecognitionService

private final class AppleSpeechRecognition: SpeechRecognitionService, @unchecked Sendable {
    private weak var transcriber: AppleSpeechTranscriber?
    init(transcriber: AppleSpeechTranscriber) { self.transcriber = transcriber }

    var providerType: ASRProviderType { .apple }

    var resultPublisher: AnyPublisher<TranscriptionResult, Error> {
        transcriber?.liveResultPublisher
            ?? Fail(error: NSError(domain: "", code: -1)).eraseToAnyPublisher()
    }

    func startRecognition(language: Locale) async throws {}
    func stopRecognition() async {}

    func checkAvailability() async -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    var supportedLanguages: [Locale] { SFSpeechRecognizer.supportedLocales().map { $0 } }
}
