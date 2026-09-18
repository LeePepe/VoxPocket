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

    fileprivate let recorder: MicrophoneRecorder
    private let whisperEngine: WhisperEngine
    private let realtimeConfig: AzureRealtimeTranscriptionConfig?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Publishers

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    // MARK: - State

    private let logger: Logger
    private let recording = HybridRecordingLifecycle()

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
        self.logger = logger
        self.realtimeConfig = realtimeConfig
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
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
        do { try await startRecording(language: language, id: id) }
        catch {
            if case .cancelStart(let session) = recording.requestStop() { session.realtime?.cancel() }
            let file = await MainActor.run { self.stopRecorder() }
            await Self.removeAudio(file)
            recording.complete(id)
            throw error
        }
    }

    private func startRecording(language: Locale, id: UUID) async throws {

        // 请求语音识别权限
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else {
            throw NSError(domain: "HybridWhisperTranscriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "语音识别权限未授权"])
        }
        try Task.checkCancellation()
        guard recording.isStarting(id) else { throw CancellationError() }

        // 更新 recognizer locale
        if speechRecognizer?.locale.language.languageCode != language.language.languageCode {
            speechRecognizer = SFSpeechRecognizer(locale: language)
        }
        guard let speechRecognizer else {
            throw NSError(domain: "HybridWhisperTranscriber", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer 不可用"])
        }

        // 清理旧任务
        recognitionTask?.finish()
        recognitionTask = nil

        // 创建识别请求
        let request = DefaultAppleSpeechRequestFactory.makeRequest()
        recognitionRequest = request
        let pipeline = realtimeConfig.map { config in
            let session = DefaultRealtimeTranscriptionSession(config: config) { [weak self] text in
                self?.receiveCloudText(text, id: id, locale: language)
            }
            return RealtimeAudioPipeline(session: session) { [weak self] in
                guard let self, let text = self.recording.restoreApplePreview(id), !text.isEmpty else { return }
                self.liveResultSubject.send(TranscriptionResult(text: text, type: .partial, confidence: nil,
                                                               timestamp: Date(), locale: language))
            }
        }
        try recording.attach(pipeline, id: id)

        // 启动录音：buffer 同步喂给 Apple Speech，同时写入 WAV 文件（由 MicrophoneRecorder 负责）
        try await recorder.startIfAllowed(shouldStart: { [recording] in recording.isStarting(id) }) { buffer in
            request.append(buffer)
            pipeline?.append(buffer)
        }
        try Task.checkCancellation()

        // 启动 Apple Speech 识别任务
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                let publish = self.recording.receiveApple(text, id: id)
                guard publish else { return }

                let transcriptionResult = TranscriptionResult(
                    text: text,
                    type: result.isFinal ? .final : .partial,
                    confidence: result.isFinal
                        ? Double(result.bestTranscription.segments.last?.confidence ?? 0)
                        : nil,
                    timestamp: Date(),
                    locale: language
                )
                self.liveResultSubject.send(transcriptionResult)
                self.logger.debug("Apple Speech: isFinal=\(result.isFinal), chars=\(text.count)")
            }

            if let error {
                let e = error as NSError
                self.logger.error("Apple Speech failed, code=\(e.code)")
            }
        }
        pipeline?.start(language: language.language.languageCode?.identifier ?? "zh")
        try recording.didStart(id)
        captureStateSubject.send(.recording)
        logger.info("Recording + Apple Speech started")
    }

    public func stop() async {
        switch recording.requestStop() {
        case .none: return
        case .cancelStart(let session):
            session.realtime?.cancel()
            await recording.waitForCleanup(session.id)
        case .finish(let session):
            await finishRecording(session)
        }
    }

    private func finishRecording(_ snapshot: HybridRecordingLifecycle.Session) async {
        defer { recording.complete(snapshot.id) }
        recognitionRequest?.endAudio()
        let fileURL = await MainActor.run { self.stopRecorder() }
        let appleSpeechText = snapshot.appleText

        guard let fileURL else {
            snapshot.realtime?.cancel()
            logger.warning("No audio file")
            return
        }

        // 实时会话必须排空/兜底，不能把尚未收到 partial 当成静默。
        guard snapshot.shouldFinalize else {
            snapshot.realtime?.cancel()
            logger.info("Apple Speech had no content → skipping Whisper")
            await Self.removeAudio(fileURL)
            return
        }

        do {
            let whisperText: String
            if let realtime = snapshot.realtime {
                whisperText = try await RealtimeASRFinalizer.resolve {
                    let text = try await realtime.finish()
                    self.logger.info("ASR completed, actual_path=realtime, chars=\(text.count)")
                    return text
                } fallback: {
                    self.logger.warning("Realtime ASR unavailable; actual_path=batch_fallback")
                    return try await self.whisperEngine.transcribe(fileURL: fileURL, language: snapshot.locale)
                }
            } else {
                whisperText = try await whisperEngine.transcribe(fileURL: fileURL, language: snapshot.locale)
            }
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

        await Self.removeAudio(fileURL)
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

    private func receiveCloudText(_ text: String, id: UUID, locale: Locale) {
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
    func checkAvailability() async -> Bool { true }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    var supportedLanguages: [Locale] { SFSpeechRecognizer.supportedLocales().map { $0 } }
}
