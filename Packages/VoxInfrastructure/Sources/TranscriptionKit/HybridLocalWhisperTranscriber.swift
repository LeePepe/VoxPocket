import VoxCore
import AVFoundation
import Combine
import Foundation
import LokiKit
import Speech
import Synchronization

/// Apple Speech + 本地 WhisperKit 混合转录器
///
/// - `MicrophoneRecorder` 负责音频采集，buffer 同时喂给 Apple Speech 和 WAV 文件写入
/// - Apple Speech 提供实时 partial 结果，驱动 UI 更新和自动停止
/// - 录音结束后，若 Apple Speech 已识别到内容，则由本地 WhisperKit 重转录获取高质量最终结果
/// - 若 Apple Speech 全程无内容（静默/噪音），跳过 WhisperKit 调用
public final class HybridLocalWhisperTranscriber: NSObject, @unchecked Sendable {

    // MARK: - Dependencies

    fileprivate let recorder: any AudioBufferSource
    private let whisperEngine: any LocalWhisperEngine
    private let batchTranscriber: any BatchTranscribing
    fileprivate let speechRecognizerProvider: any SpeechRecognizing
    fileprivate let speechAuthorizationProvider: any SpeechAuthorizationProviding
    private let whisperConfig: LocalWhisperKitConfig
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: (any SpeechRecognitionTasking)?

    // MARK: - Publishers

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)
    private let _modelLoadingStateSubject = CurrentValueSubject<ModelLoadingState, Never>(.idle)

    // MARK: - State

    private let _isTranscribing = Mutex(false)
    private let logger: any VoxLogger
    private var recordingLocale: Locale = Locale(identifier: "zh-Hans")
    /// Apple Speech 是否识别到任何文字（用于决定是否调用 WhisperKit）
    private var appleHasContent = false
    /// Apple Speech 最新识别文本（用于与 WhisperKit 结果合并）
    private var appleLatestText: String = ""

    // MARK: - 多识别器结果合并

    /// 可选的 LLM 合并器：当两路识别器都有结果时，将两路文本交给 LLM 得出最终文本。
    /// 注：此属性在 ServiceContainer 初始化阶段（单线程）设置，之后只读，故标记为 nonisolated(unsafe)。
    public nonisolated(unsafe) var merger: (any TranscriptionMerger)?

    // MARK: - Sub-services

    private lazy var _audioCaptureService: HybridLocalAudioCapture = HybridLocalAudioCapture(transcriber: self)
    private lazy var _speechRecognitionService: HybridLocalSpeechRecognition = HybridLocalSpeechRecognition(transcriber: self)

    // MARK: - Init

    public init(
        config: LocalWhisperKitConfig = .default,
        logger: any VoxLogger = NoopVoxLogger(),
        storageLocations: VoxStorageLocations
    ) {
        self.whisperConfig = config
        self.recorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "HybridLocalWhisperTranscriber.Mic"))
        let engine = SharedLocalWhisperEngineHandle(config: config, logger: logger, storageLocations: storageLocations)
        self.whisperEngine = engine
        self.batchTranscriber = LocalWhisperBatchAdapter(engine: engine, config: config)
        self.speechRecognizerProvider = SystemSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        self.speechAuthorizationProvider = SystemSpeechAuthorizationProvider()
        self.logger = logger
        super.init()

        if config.preloadOnStart {
            startBackgroundPreload()
        }
    }

    internal init(recorder: any AudioBufferSource,
                  speechRecognizer: any SpeechRecognizing,
                  speechAuthorizationProvider: any SpeechAuthorizationProviding,
                  batchTranscriber: any BatchTranscribing,
                  whisperEngine: any LocalWhisperEngine,
                  config: LocalWhisperKitConfig = .default,
                  logger: any VoxLogger = NoopVoxLogger()) {
        self.recorder = recorder
        self.speechRecognizerProvider = speechRecognizer
        self.speechAuthorizationProvider = speechAuthorizationProvider
        self.batchTranscriber = batchTranscriber
        self.whisperEngine = whisperEngine
        self.whisperConfig = config
        self.logger = logger
        super.init()
    }

    // MARK: - Private

    private func startBackgroundPreload() {
        Task { [weak self] in
            guard let self else { return }
            do {
                self._modelLoadingStateSubject.send(.loading)
                try await self.whisperEngine.prepare(onProgress: { [weak self] progress in
                    self?._modelLoadingStateSubject.send(.downloading(progress: progress))
                })
                self._modelLoadingStateSubject.send(.ready)
            } catch {
                self._modelLoadingStateSubject.send(.failed(error.localizedDescription))
            }
        }
    }

    @discardableResult
    private func stopRecorder() -> URL? {
        let url = recorder.stop()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        captureStateSubject.send(.idle)
        _isTranscribing.withLock { $0 = false }
        return url
    }
}

// MARK: - TranscriptionCoordinator

extension HybridLocalWhisperTranscriber: MultiRecognizerTranscriber {

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
        _isTranscribing.withLock { $0 }
    }

    public func start(language: Locale) async throws {
        logger.info("start()", fields: [.label("language", .source("locale"))])

        if _isTranscribing.withLock({ $0 }) {
            logger.warning("Already transcribing, stopping first")
            await stop()
        }

        recordingLocale = language
        appleHasContent = false

        let speechAuthorized = await speechAuthorizationProvider.requestSpeechAuthorization()
        guard speechAuthorized else {
            throw NSError(domain: "HybridLocalWhisperTranscriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "语音识别权限未授权"])
        }

        guard speechRecognizerProvider.isAvailable(for: language) else {
            throw NSError(domain: "HybridLocalWhisperTranscriber", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer 不可用"])
        }

        recognitionTask?.finish()
        recognitionTask = nil

        let request = DefaultAppleSpeechRequestFactory.makeRequest()
        recognitionRequest = request

        // buffer 同步喂给 Apple Speech，同时写入 WAV 文件（由 MicrophoneRecorder 负责）
        try await recorder.start { buffer in
            request.append(buffer)
        }

        captureStateSubject.send(.recording)
        _isTranscribing.withLock { $0 = true }
        logger.info("Recording + Apple Speech started")

        do {
            recognitionTask = try speechRecognizerProvider.recognitionTask(locale: language, request: request) { [weak self] update in
            guard let self else { return }
            let text = update.text ?? ""
            if !text.isEmpty {
                self.appleHasContent = true
                self.appleLatestText = text
            }
            self.liveResultSubject.send(TranscriptionResult(text: text, type: update.isFinal ? .final : .partial,
                confidence: update.confidence.map(Double.init), timestamp: Date(), locale: language))
            if let recognitionError = update.error {
                let e = recognitionError as NSError
                self.logger.error("Apple Speech error", fields: [.int("code", e.code)])
                self.stopRecorder()
            }
            }
        } catch {
            _ = stopRecorder()
            throw error
        }
    }

    public func stop() async {
        logger.info("stop() called", fields: [.bool("has_content", appleHasContent)])

        recognitionRequest?.endAudio()
        let fileURL = stopRecorder()
        let hadContent = appleHasContent
        let appleSpeechText = appleLatestText
        appleHasContent = false
        appleLatestText = ""

        guard let fileURL else {
            logger.warning("No audio file")
            return
        }

        defer { try? FileManager.default.removeItem(at: fileURL) }

        guard hadContent else {
            logger.info("Apple Speech had no content → skipping WhisperKit")
            return
        }

        do {
            logger.info("Apple Speech had content → submitting to local WhisperKit")
            // 确保模型已加载
            if _modelLoadingStateSubject.value != .ready {
                _modelLoadingStateSubject.send(.loading)
                try await whisperEngine.prepare(onProgress: { [weak self] progress in
                    self?._modelLoadingStateSubject.send(.downloading(progress: progress))
                })
                _modelLoadingStateSubject.send(.ready)
            }

            let whisperText = try await batchTranscriber.transcribe(fileURL: fileURL, language: recordingLocale)
            guard !whisperText.isEmpty else {
                logger.warning("WhisperKit returned empty result")
                return
            }
            logger.info("WhisperKit result", fields: [.int("text_length", whisperText.count)])

            let useMerger = merger != nil && !appleSpeechText.isEmpty && appleSpeechText != whisperText
            if useMerger { logger.info("Merging Apple Speech + WhisperKit via LLM") }

            let finalText = await mergedTranscription(
                appleSpeech: appleSpeechText,
                whisper: whisperText,
                merger: merger
            )

            let result = TranscriptionResult(
                text: finalText, type: .final,
                confidence: nil, timestamp: Date(), locale: recordingLocale
            )
            // LLM 合并后直接 commit，不再通过 liveResultSubject 推中间更新
            // 非 LLM 路径（纯 WhisperKit）保持原有行为，同时更新 live 显示
            if !useMerger { liveResultSubject.send(result) }
            finalResultSubject.send(result)
        } catch {
            logger.error("WhisperKit error")
        }
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

// MARK: - ModelLoadingObservable

extension HybridLocalWhisperTranscriber: ModelLoadingObservable {
    public var modelLoadingState: ModelLoadingState {
        _modelLoadingStateSubject.value
    }

    public var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> {
        _modelLoadingStateSubject.eraseToAnyPublisher()
    }
}

// MARK: - ModelPreloadControlling

extension HybridLocalWhisperTranscriber: ModelPreloadControlling {
    public func startModelPreloadIfNeeded() {
        guard _modelLoadingStateSubject.value == .idle else { return }
        startBackgroundPreload()
    }
}

extension HybridLocalWhisperTranscriber: ModelLoadingStartControlling {
    public var blocksRecordingUntilModelReady: Bool {
        false
    }
}

// MARK: - Internal AudioCaptureService

private final class HybridLocalAudioCapture: AudioCaptureService, @unchecked Sendable {
    private weak var transcriber: HybridLocalWhisperTranscriber?
    init(transcriber: HybridLocalWhisperTranscriber) { self.transcriber = transcriber }

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

private final class HybridLocalSpeechRecognition: SpeechRecognitionService, @unchecked Sendable {
    private weak var transcriber: HybridLocalWhisperTranscriber?
    init(transcriber: HybridLocalWhisperTranscriber) { self.transcriber = transcriber }

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
