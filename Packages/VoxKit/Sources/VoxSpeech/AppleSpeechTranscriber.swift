import AVFoundation
import Foundation
import VoxCore
import Speech
import Synchronization

/// Apple Speech Framework 转录协调器
///
/// 使用 `MicrophoneRecorder` 采集音频，`SFSpeechRecognizer` 实时识别文字。
public final class AppleSpeechTranscriber: NSObject, @unchecked Sendable { // Sendable: Apple Speech (SFSpeechRecognizer/SFSpeechAudioBufferRecognitionRequest/SFSpeechRecognitionTask) callback boundary; all mutable state is guarded by stateMutex.

    // MARK: - Dependencies

    fileprivate let recorder: any AudioBufferSource
    fileprivate let speechRecognizerProvider: any SpeechRecognizing
    fileprivate let speechAuthorizationProvider: any SpeechAuthorizationProviding
    private struct State: @unchecked Sendable { // Sendable: Apple Speech request/task callback references are guarded by stateMutex.
        var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
        var recognitionTask: (any SpeechRecognitionTasking)?
    }
    private let stateMutex = Mutex(State())
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest? {
        get { stateMutex.withLock { $0.recognitionRequest } }
        set { stateMutex.withLock { $0.recognitionRequest = newValue } }
    }
    private var recognitionTask: (any SpeechRecognitionTasking)? {
        get { stateMutex.withLock { $0.recognitionTask } }
        set { stateMutex.withLock { $0.recognitionTask = newValue } }
    }

    // MARK: - Publishers

    package let sessionRelay = SpeechSessionRelay()
    fileprivate let captureStateSubject = AsyncValueRelay<AudioCaptureState>(.idle)

    // MARK: - State

    private let recording = HybridRecordingLifecycle()
    private let sessionEffects: QuickRecordingSessionEffects?
    private let temporaryAudioStore: TemporaryAudioStore?
    private let logger: any VoxLogger

    // MARK: - Sub-services


    // MARK: - Init

    public init(locale: Locale = Locale(identifier: "zh-Hans"), logger: any VoxLogger = NoopVoxLogger(),
                storageLocations: VoxStorageLocations) {
        recorder = MicrophoneRecorder(logger: logger, storageLocations: storageLocations)
        speechRecognizerProvider = SystemSpeechRecognizer(locale: locale)
        speechAuthorizationProvider = SystemSpeechAuthorizationProvider()
        self.logger = logger
        temporaryAudioStore = TemporaryAudioStore(storageLocations: storageLocations)
        sessionEffects = nil
        super.init()
    }

    init(effects: QuickRecordingSessionEffects) {
        recorder = SyntheticAudioBufferSource()
        temporaryAudioStore = nil
        speechRecognizerProvider = SystemSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        speechAuthorizationProvider = SystemSpeechAuthorizationProvider()
        logger = NoopVoxLogger()
        sessionEffects = effects
        super.init()
    }

    internal init(recorder: any AudioBufferSource,
                  speechRecognizer: any SpeechRecognizing,
                  speechAuthorizationProvider: any SpeechAuthorizationProviding,
                  logger: any VoxLogger = NoopVoxLogger(),
                  storageLocations: VoxStorageLocations) {
        self.temporaryAudioStore = TemporaryAudioStore(storageLocations: storageLocations)
        self.recorder = recorder
        self.speechRecognizerProvider = speechRecognizer
        self.speechAuthorizationProvider = speechAuthorizationProvider
        self.logger = logger
        self.sessionEffects = nil
        super.init()
    }
}

// MARK: - TranscriptionCoordinator

extension AppleSpeechTranscriber: SpeechAvailabilityProviding, SessionDriving {

    package var finishesRelayOnStopReturn: Bool { false }

    public var isSpeechAvailable: Bool { hasSpeechPermission && speechRecognizerProvider.isAvailable }
    public var providerKind: ASRProviderType { .apple }
    public var supportedLanguages: [Locale] { SFSpeechRecognizer.supportedLocales().map { $0 } }
    public var isActive: Bool { isTranscribing }
    public var hasMicrophonePermission: Bool { recorder.hasPermission }
    public var hasSpeechPermission: Bool { speechAuthorizationProvider.speechAuthorizationStatus == .authorized }
    public func requestMicrophonePermission() async -> Bool { await recorder.requestPermission() }
    public func requestSpeechPermission() async -> Bool { await speechAuthorizationProvider.requestSpeechAuthorization() }
    public func captureStates() -> AsyncStream<AudioCaptureState> { captureStateSubject.stream() }
    public func audioLevels() -> AsyncStream<Float> { recorder.audioLevels() }
    package func captureDeviceStates() -> AsyncStream<AudioCaptureState> { recorder.captureStates() }
    package func interruptCapture() async {
        await stop()
        captureStateSubject.send(.interrupted)
        sessionRelay.send(.state(.interrupted))
    }


    public var isTranscribing: Bool {
        recording.isRecording
    }

    public func start(language: Locale) async throws {
        logger.info("start()", fields: [.label("language", .source("locale"))])

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
                captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
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
        guard speechRecognizerProvider.isAvailable(for: language) else {
            throw NSError(domain: "AppleSpeechTranscriber", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer 不可用"])
        }
        recognitionTask?.finish()
        recognitionTask = nil
        let request = DefaultAppleSpeechRequestFactory.makeRequest()
        recognitionRequest = request
        try await recorder.startIfAllowed(shouldStart: { [recording] in recording.isStarting(id) }) { buffer in
            request.append(buffer)
        }
        try Task.checkCancellation()
        do {
            try startAppleTask(request: request, language: language, id: id)
        } catch {
            _ = recorder.stop()
            recognitionRequest = nil
            recognitionTask = nil
            captureStateSubject.send(.idle); sessionRelay.send(.state(.idle))
            throw error
        }
        try recording.didStart(id)
        captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
        logger.info("Recording + recognition started")
    }

    private func authorizeSpeech() async throws {
        let speechAuthorized = await speechAuthorizationProvider.requestSpeechAuthorization()
        guard speechAuthorized else {
            throw NSError(domain: "AppleSpeechTranscriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "语音识别权限未授权"])
        }

    }

    private func startAppleTask(request: SFSpeechAudioBufferRecognitionRequest,
                                language: Locale, id: UUID) throws {
        recognitionTask = try speechRecognizerProvider.recognitionTask(locale: language, request: request) { [weak self] update in
            guard let self, self.recording.acceptsAppleResult(id) else { return }
            if let text = update.text {
                let result = TranscriptionResult(text: text, type: update.isFinal ? .final : .partial,
                    confidence: update.confidence.map(Double.init), timestamp: Date(), locale: language)
                self.receiveAppleResult(result, id: id)
                if update.isFinal { self.recognitionTask = nil }
            }
            if let error = update.error {
                let e = error as NSError
                if e.code == 301 || e.code == NSURLErrorCancelled { self.logger.debug("Recognition task ended") }
                else { self.logger.error("Recognition error", fields: [.int("error_code", e.code)]) }
                self.recognitionTask = nil
            }
        }
    }

    private func receiveAppleResult(_ result: TranscriptionResult, id: UUID) {
        _ = recording.receiveApple(result.text, id: id, retainText: false)
        guard recording.acceptsAppleResult(id) else { return }
        sessionRelay.send(.partial(result))
        if result.isFinal { sessionRelay.send(.final(result)) }
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
        captureStateSubject.send(.idle); sessionRelay.send(.state(.idle))
        return file
    }

    private func removeAudio(_ file: URL?) async throws {
        if let sessionEffects { try await sessionEffects.removeAudio(file); return }
        guard let file else { return }
        let store = temporaryAudioStore
        await Task.detached { try? store?.remove(file) }.value
    }

    public func pause() {
        recorder.pause()
        captureStateSubject.send(.paused); sessionRelay.send(.state(.paused))
    }

    public func resume() {
        recorder.resume()
        captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
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
