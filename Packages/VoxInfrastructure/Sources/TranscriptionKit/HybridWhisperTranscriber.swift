import VoxCore
import AVFoundation
import Combine
import Foundation
import LokiKit
import Speech

/// Apple Speech + Azure Whisper 混合转录器
///
/// - `MicrophoneRecorder` 负责音频采集，buffer 同时喂给 Apple Speech 和 WAV 文件写入
/// - Apple Speech 提供实时 partial 结果，驱动 UI 更新和自动停止
/// - 可选云端实时 ASR 在录音期间发送音频；失败时才由 `WhisperEngine` 获取终稿
/// - 若 Apple Speech 全程无内容（静默/噪音），跳过 Whisper API 调用
// Combine publisher 桥接沿用 unchecked Sendable；跨回调的会话数据由 Mutex 保护。
public final class HybridWhisperTranscriber: NSObject, @unchecked Sendable {

    // MARK: - Dependencies

    fileprivate let recorder: any AudioBufferSource
    private let whisperEngine: any BatchTranscribing
    private let realtimeConfig: AzureRealtimeTranscriptionConfig?
    fileprivate let speechRecognizerProvider: any SpeechRecognizing
    fileprivate let speechAuthorizationProvider: any SpeechAuthorizationProviding
    private let realtimeSessionMaker: any RealtimeSessionMaking
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: (any SpeechRecognitionTasking)?

    // MARK: - Publishers

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    // MARK: - State

    private let logger: Logger
    private let recording = HybridRecordingLifecycle()
    private let sessionEffects: QuickRecordingSessionEffects?

    // MARK: - 多识别器结果合并

    /// 可选的 LLM 合并器；在 ServiceContainer 初始化阶段（单线程）设置，之后只读
    public nonisolated(unsafe) var merger: (any TranscriptionMerger)?

    // MARK: - Sub-services

    private lazy var _audioCaptureService: HybridAudioCapture = HybridAudioCapture(transcriber: self)
    private lazy var _speechRecognitionService: HybridSpeechRecognition = HybridSpeechRecognition(transcriber: self)

    // MARK: - Init

    public init(
        whisperConfig: AzureWhisperConfig,
        realtimeConfig: AzureRealtimeTranscriptionConfig? = nil,
        logger: Logger = PrintLogger(subsystem: "HybridWhisperTranscriber"),
        session: URLSession = .shared
    ) {
        self.recorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "HybridWhisperTranscriber.Mic"))
        self.whisperEngine = WhisperEngine(config: whisperConfig, session: session,
                                           logger: PrintLogger(subsystem: "WhisperEngine"))
        self.speechRecognizerProvider = SystemSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        self.speechAuthorizationProvider = SystemSpeechAuthorizationProvider()
        self.realtimeSessionMaker = DefaultRealtimeSessionMaker()
        self.logger = logger
        self.realtimeConfig = realtimeConfig
        self.sessionEffects = nil
        super.init()
    }

    init(whisperConfig: AzureWhisperConfig, effects: QuickRecordingSessionEffects) {
        recorder = MicrophoneRecorder()
        whisperEngine = WhisperEngine(config: whisperConfig)
        speechRecognizerProvider = SystemSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        speechAuthorizationProvider = SystemSpeechAuthorizationProvider()
        realtimeSessionMaker = DefaultRealtimeSessionMaker()
        realtimeConfig = nil
        logger = PrintLogger(subsystem: "HybridWhisperTranscriber")
        sessionEffects = effects
        super.init()
    }

    internal init(recorder: any AudioBufferSource,
                  speechRecognizer: any SpeechRecognizing,
                  speechAuthorizationProvider: any SpeechAuthorizationProviding,
                  whisperEngine: any BatchTranscribing,
                  realtimeSessionMaker: any RealtimeSessionMaking,
                  realtimeConfig: AzureRealtimeTranscriptionConfig? = nil,
                  logger: Logger = PrintLogger(subsystem: "HybridWhisperTranscriber")) {
        self.recorder = recorder
        self.speechRecognizerProvider = speechRecognizer
        self.speechAuthorizationProvider = speechAuthorizationProvider
        self.whisperEngine = whisperEngine
        self.realtimeSessionMaker = realtimeSessionMaker
        self.realtimeConfig = realtimeConfig
        self.logger = logger
        self.sessionEffects = nil
        super.init()
    }
}

// MARK: - TranscriptionCoordinator

extension HybridWhisperTranscriber: MultiRecognizerTranscriber {

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
            captureStateSubject.send(.idle)
            throw error
        }
        await realtime.0?.start(language: language)
        try recording.didStart(id)
        captureStateSubject.send(.recording)
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
            self.liveResultSubject.send(TranscriptionResult(text: text, type: .partial, confidence: nil,
                                                           timestamp: Date(), locale: language))
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
                self.logger.error("Apple Speech failed, code=\((recognitionError as NSError).code)")
            }
        }
    }

    private func receiveAppleResult(_ result: TranscriptionResult, id: UUID) {
        guard recording.receiveApple(result.text, id: id) else { return }
        liveResultSubject.send(result)
    }

    public func stop() async {
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
            if !useMerger { liveResultSubject.send(result) }
            finalResultSubject.send(result)
        } catch {
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
            self.logger.info("ASR completed, actual_path=realtime, chars=\(text.count)")
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
            captureStateSubject.send(.idle)
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
        else { await Self.removeAudio(file) }
    }

    public func pause() {
        recorder.pause()
        captureStateSubject.send(.paused)
    }

    public func resume() {
        recorder.resume()
        captureStateSubject.send(.recording)
    }

    // MARK: - Private

    func receiveCloudText(_ text: String, id: UUID, locale: Locale) {
        let active = recording.receiveCloud(text, id: id)
        guard active, !text.isEmpty else { return }
        liveResultSubject.send(TranscriptionResult(text: text, type: .partial, confidence: nil,
                                                   timestamp: Date(), locale: locale))
    }

    private static func removeAudio(_ url: URL?) async {
        guard let url else { return }
        await Task.detached { try? FileManager.default.removeItem(at: url) }.value
    }

    @discardableResult
    private func stopRecorder() -> URL? {
        let url = recorder.stop()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        captureStateSubject.send(.idle)
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

// MARK: - Internal AudioCaptureService

private final class HybridAudioCapture: AudioCaptureService, @unchecked Sendable {
    private weak var transcriber: HybridWhisperTranscriber?
    init(transcriber: HybridWhisperTranscriber) { self.transcriber = transcriber }

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
    func requestPermission() async -> Bool { await transcriber?.recorder.requestPermission() ?? false }
    var hasPermission: Bool { transcriber?.recorder.hasPermission ?? false }
}

// MARK: - Internal SpeechRecognitionService

private final class HybridSpeechRecognition: SpeechRecognitionService, @unchecked Sendable {
    private weak var transcriber: HybridWhisperTranscriber?
    init(transcriber: HybridWhisperTranscriber) { self.transcriber = transcriber }

    var providerType: ASRProviderType { .whisper }

    var resultPublisher: AnyPublisher<TranscriptionResult, Error> {
        transcriber?.liveResultPublisher
            ?? Fail(error: NSError(domain: "", code: -1)).eraseToAnyPublisher()
    }

    func startRecognition(language: Locale) async throws {}
    func stopRecognition() async {}
    func checkAvailability() async -> Bool {
        transcriber?.speechAuthorizationProvider.speechAuthorizationStatus == .authorized
            && transcriber?.speechRecognizerProvider.isAvailable == true
    }

    func requestPermission() async -> Bool {
        await transcriber?.speechAuthorizationProvider.requestSpeechAuthorization() ?? false
    }

    var supportedLanguages: [Locale] { SFSpeechRecognizer.supportedLocales().map { $0 } }
}
