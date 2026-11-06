import AVFoundation
import Foundation
import VoxCore
import Speech
import Synchronization

/// Apple Speech + Azure Whisper 混合转录器
///
/// - `MicrophoneRecorder` 负责音频采集，buffer 同时喂给 Apple Speech 和 WAV 文件写入
/// - Apple Speech 提供实时 partial 结果，驱动 UI 更新和自动停止
/// - 可选云端实时 ASR 在录音期间发送音频；失败时才由 `WhisperEngine` 获取终稿
/// - 若 Apple Speech 全程无内容（静默/噪音），跳过 Whisper API 调用
public final class HybridWhisperTranscriber: NSObject, @unchecked Sendable { // Sendable: Apple Speech (SFSpeechRecognizer/SFSpeechAudioBufferRecognitionRequest/SFSpeechRecognitionTask) callback boundary; all mutable state is guarded by stateMutex.

    // MARK: - Dependencies

    fileprivate let recorder: any AudioBufferSource
    private let whisperEngine: any BatchTranscribing
    private let realtimeConfig: AzureRealtimeTranscriptionConfig?
    fileprivate let speechRecognizerProvider: any SpeechRecognizing
    fileprivate let speechAuthorizationProvider: any SpeechAuthorizationProviding
    private let realtimeSessionMaker: any RealtimeSessionMaking
    private struct State: @unchecked Sendable { // Sendable: Apple Speech request/task references are guarded by stateMutex; only framework-safe append/end/finish/cancel operations cross the callback boundary.
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

    private let temporaryAudioStore: TemporaryAudioStore?
    private let logger: any VoxLogger
    private let recording = HybridRecordingLifecycle()
    private let sessionEffects: QuickRecordingSessionEffects?

    // MARK: - 多识别器结果合并

    /// 可选的 LLM 合并器；在构造时注入，之后不可变。
    public let merger: (any TranscriptionMerger)?

    // MARK: - Sub-services


    // MARK: - Init

    public init(
        whisperConfig: AzureWhisperConfig,
        realtimeConfig: AzureRealtimeTranscriptionConfig? = nil,
        logger: any VoxLogger = NoopVoxLogger(),
        session: URLSession = .shared,
        merger: (any TranscriptionMerger)? = nil,
        storageLocations: VoxStorageLocations
    ) {
        self.recorder = MicrophoneRecorder(logger: logger, storageLocations: storageLocations)
        self.temporaryAudioStore = TemporaryAudioStore(storageLocations: storageLocations)
        self.whisperEngine = WhisperEngine(config: whisperConfig, session: session,
                                           logger: logger, storageLocations: storageLocations)
        self.speechRecognizerProvider = SystemSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        self.speechAuthorizationProvider = SystemSpeechAuthorizationProvider()
        self.realtimeSessionMaker = DefaultRealtimeSessionMaker()
        self.logger = logger
        self.realtimeConfig = realtimeConfig
        self.merger = merger
        self.sessionEffects = nil
        super.init()
    }

    package init(whisperConfig: AzureWhisperConfig, effects: QuickRecordingSessionEffects, merger: (any TranscriptionMerger)? = nil) {
        recorder = SyntheticAudioBufferSource()
        temporaryAudioStore = nil
        whisperEngine = EffectOnlyBatchTranscriber()
        speechRecognizerProvider = SystemSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        speechAuthorizationProvider = SystemSpeechAuthorizationProvider()
        realtimeSessionMaker = DefaultRealtimeSessionMaker()
        realtimeConfig = nil
        logger = NoopVoxLogger()
        sessionEffects = effects
        self.merger = merger
        super.init()
    }

    package init(recorder: any AudioBufferSource,
                  speechRecognizer: any SpeechRecognizing,
                  speechAuthorizationProvider: any SpeechAuthorizationProviding,
                  whisperEngine: any BatchTranscribing,
                  realtimeSessionMaker: any RealtimeSessionMaking,
                  realtimeConfig: AzureRealtimeTranscriptionConfig? = nil,
                  logger: any VoxLogger = NoopVoxLogger(),
                  merger: (any TranscriptionMerger)? = nil,
                  storageLocations: VoxStorageLocations) {
        self.temporaryAudioStore = TemporaryAudioStore(storageLocations: storageLocations)
        self.recorder = recorder
        self.speechRecognizerProvider = speechRecognizer
        self.speechAuthorizationProvider = speechAuthorizationProvider
        self.whisperEngine = whisperEngine
        self.realtimeSessionMaker = realtimeSessionMaker
        self.realtimeConfig = realtimeConfig
        self.logger = logger
        self.merger = merger
        self.sessionEffects = nil
        super.init()
    }
}

// MARK: - TranscriptionCoordinator

extension HybridWhisperTranscriber: SpeechAvailabilityProviding, SessionDriving, MultiRecognizerSpeechSource {


    public var isSpeechAvailable: Bool { hasSpeechPermission && speechRecognizerProvider.isAvailable }
    public var providerKind: ASRProviderType { .whisper }
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
        }
        catch {
            if let snapshot = recording.session(id) { try? await discardRecording(snapshot) }
            recording.complete(id)
            throw error
        }
    }

    private func startRecording(language: Locale, id: UUID) async throws {
        try await authorizeSpeech()
        try Task.checkCancellation()
        guard recording.isStarting(id) else { throw CancellationError() }
        guard speechRecognizerProvider.isAvailable(for: language) else {
            throw NSError(domain: "HybridWhisperTranscriber", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer 不可用"])
        }
        recognitionTask?.finish()
        recognitionTask = nil
        let request = DefaultAppleSpeechRequestFactory.makeRequest()
        recognitionRequest = request
        let realtime = makeRealtime(language: language, id: id)
        try recording.attach(realtime.0, id: id, cancelRealtime: realtime.1)
        try await recorder.startIfAllowed(shouldStart: { [recording] in recording.isStarting(id) }) { buffer in
            request.append(buffer)
            realtime.0?.append(buffer)
        }
        try Task.checkCancellation()
        do {
            try startAppleTask(request: request, language: language, id: id)
        } catch {
            await realtime.0?.cancel()
            _ = recorder.stop()
            recognitionRequest = nil
            recognitionTask = nil
            captureStateSubject.send(.idle); sessionRelay.send(.state(.idle))
            throw error
        }
        await realtime.0?.start(language: language)
        try recording.didStart(id)
        captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
        logger.info("Recording + Apple Speech started")
    }

    private func authorizeSpeech() async throws {
        let speechAuthorized = await speechAuthorizationProvider.requestSpeechAuthorization()
        guard speechAuthorized else {
            throw NSError(domain: "HybridWhisperTranscriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "语音识别权限未授权"])
        }
    }

    private func makeRealtime(language: Locale, id: UUID)
        -> ((any RealtimePipelining)?, (@Sendable () async -> Void)?) {
        guard let config = realtimeConfig else { return (nil, nil) }
        let pipeline = realtimeSessionMaker.makePipeline(config: config, onPartial: { [weak self] text in
            self?.receiveCloudText(text, id: id, locale: language)
        }, onFallback: { [weak self] in
            guard let self, let text = self.recording.restoreApplePreview(id), !text.isEmpty else { return }
            self.sessionRelay.send(.partial(TranscriptionResult(text: text, type: .partial, confidence: nil,
                                                           timestamp: Date(), locale: language)))
        })
        return (pipeline, { await pipeline.cancelQuickRecording() })
    }

    private func startAppleTask(request: SFSpeechAudioBufferRecognitionRequest,
                                language: Locale, id: UUID) throws {
        recognitionTask = try speechRecognizerProvider.recognitionTask(locale: language, request: request) { [weak self] update in
            guard let self else { return }
            if let text = update.text {
                self.receiveAppleResult(TranscriptionResult(text: text, type: update.isFinal ? .final : .partial,
                    confidence: update.confidence.map(Double.init), timestamp: Date(), locale: language), id: id)
            }
            if let recognitionError = update.error {
                self.logger.error("Apple Speech failed", fields: [.int("error_code", (recognitionError as NSError).code)])
            }
        }
    }

    private func receiveAppleResult(_ result: TranscriptionResult, id: UUID) {
        guard recording.receiveApple(result.text, id: id) else { return }
        sessionRelay.send(.partial(result))
    }

    public func stop() async {
        defer { sessionRelay.finish() }

        switch recording.requestStop() {
        case .none: return
        case .cancelStart(let session):
            await session.realtime?.cancel()
            await recording.waitForCleanup(session.id)
        case .finish(let session):
            await finishRecording(session)
        case .discard(let session):
            try? await discardRecording(session)
            recording.complete(session.id)
        }
    }

    private func finishRecording(_ snapshot: HybridRecordingLifecycle.Session) async {
        defer { recording.complete(snapshot.id) }
        if let sessionEffects { sessionEffects.endAppleAudio() }
        else { recognitionRequest?.endAudio() }
        let fileURL = await stopCapture()
        let appleSpeechText = snapshot.appleText

        guard let fileURL else {
            await snapshot.realtime?.cancel()
            logger.warning("No audio file")
            return
        }

        // 实时会话必须排空/兜底，不能把尚未收到 partial 当成静默。
        guard snapshot.shouldFinalize else {
            await snapshot.realtime?.cancel()
            logger.info("Apple Speech had no content → skipping Whisper")
            try? await removeAudio(fileURL)
            return
        }

        do {
            let whisperText = try await transcribe(snapshot, fileURL: fileURL)
            let useMerger = merger != nil && !appleSpeechText.isEmpty && appleSpeechText != whisperText
            if useMerger { logger.info("Merging Apple Speech + Whisper via LLM") }

            let finalText = await mergedTranscription(
                appleSpeech: appleSpeechText,
                whisper: whisperText,
                merger: merger
            )
            let result = TranscriptionResult(
                text: finalText, type: .final,
                confidence: nil, timestamp: Date(), locale: snapshot.locale
            )
            if !useMerger { sessionRelay.send(.partial(result)) }
            sessionRelay.send(.final(result))
        } catch {
            sessionRelay.finish(throwing: error)
            logger.error("ASR finalization failed")
        }

        try? await removeAudio(fileURL)
    }

    private func transcribe(_ snapshot: HybridRecordingLifecycle.Session, fileURL: URL) async throws -> String {
        if let sessionEffects { return try await sessionEffects.finalize(snapshot.locale) }
        guard let realtime = snapshot.realtime else {
            return try await whisperEngine.transcribe(fileURL: fileURL, language: snapshot.locale)
        }
        return try await RealtimeASRFinalizer.resolve {
            let text = try await realtime.finish()
            self.logger.info("ASR completed", fields: [.label("path", .source("realtime")), .int("text_length", text.count)])
            return text
        } fallback: {
            self.logger.warning("Realtime ASR unavailable; actual_path=batch_fallback")
            return try await self.whisperEngine.transcribe(fileURL: fileURL, language: snapshot.locale)
        }
    }

    private func stopCapture() async -> URL? {
        if let sessionEffects {
            let url = await sessionEffects.stopCapture()
            sessionEffects.cancelApple()
            captureStateSubject.send(.idle); sessionRelay.send(.state(.idle))
            return url
        }
        return await MainActor.run { self.stopRecorder() }
    }

    private func discardRecording(_ snapshot: HybridRecordingLifecycle.Session) async throws {
        let file = await stopCapture()
        if let sessionEffects { await sessionEffects.cancelRealtime() }
        else if let cancel = snapshot.cancelRealtime { await cancel() }
        else { await snapshot.realtime?.cancel() }
        try await removeAudio(file)
    }

    private func removeAudio(_ file: URL?) async throws {
        if let sessionEffects { try await sessionEffects.removeAudio(file) }
        else if let file, let store = temporaryAudioStore { try await Task.detached { try store.remove(file) }.value }
    }

    public func pause() {
        recorder.pause()
        captureStateSubject.send(.paused); sessionRelay.send(.state(.paused))
    }

    public func resume() {
        recorder.resume()
        captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
    }

    // MARK: - Private

    func receiveCloudText(_ text: String, id: UUID, locale: Locale) {
        let active = recording.receiveCloud(text, id: id)
        guard active, !text.isEmpty else { return }
        sessionRelay.send(.partial(TranscriptionResult(text: text, type: .partial, confidence: nil,
                                                   timestamp: Date(), locale: locale)))
    }

    @discardableResult
    private func stopRecorder() -> URL? {
        let url = recorder.stop()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        captureStateSubject.send(.idle); sessionRelay.send(.state(.idle))
        return url
    }
}

extension HybridWhisperTranscriber: QuickRecordingReleaseControlling {
    public func prepareQuickRecording() throws { try recording.prepareQuickRecording() }

    public func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        try recording.freezeQuickRecordingRelease()
    }

    public func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        if snapshot.hasRecognizedSpeech { await recording.waitForStartup(snapshot.sessionID) }
        switch recording.claimQuickRelease(snapshot) {
        case .none: return
        case .cancelStart(let session):
            await recording.waitForCleanup(session.id)
        case .finish(let session):
            await finishRecording(session)
        case .discard(let session):
            defer { recording.complete(session.id) }
            try await discardRecording(session)
        }
    }
}
