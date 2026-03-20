import AVFoundation
import Combine
import Foundation
import Observability
import Speech
import Synchronization

/// Apple Speech + Azure Whisper 混合转录器
///
/// - `MicrophoneRecorder` 负责音频采集，buffer 同时喂给 Apple Speech 和 WAV 文件写入
/// - Apple Speech 提供实时 partial 结果，驱动 UI 更新和自动停止
/// - 录音结束后，若 Apple Speech 已识别到内容，则由 `WhisperEngine` 提交获取高质量最终结果
/// - 若 Apple Speech 全程无内容（静默/噪音），跳过 Whisper API 调用
public final class HybridWhisperTranscriber: NSObject, @unchecked Sendable {

    // MARK: - Dependencies

    fileprivate let recorder: MicrophoneRecorder
    private let whisperEngine: WhisperEngine
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Publishers

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    // MARK: - State

    private let _isTranscribing = Mutex(false)
    private let logger: Logger
    private var recordingLocale: Locale = Locale(identifier: "zh-Hans")
    /// Apple Speech 是否识别到任何文字（用于决定是否调用 Whisper）
    private var appleHasContent = false
    /// Apple Speech 最新识别文本（用于与 Whisper 结果合并）
    private var appleLatestText: String = ""

    // MARK: - 多识别器结果合并

    /// 可选的 LLM 合并器；在 ServiceContainer 初始化阶段（单线程）设置，之后只读
    public nonisolated(unsafe) var merger: (any TranscriptionMerger)?

    // MARK: - Sub-services

    private lazy var _audioCaptureService: HybridAudioCapture = HybridAudioCapture(transcriber: self)
    private lazy var _speechRecognitionService: HybridSpeechRecognition = HybridSpeechRecognition(transcriber: self)

    // MARK: - Init

    public init(
        whisperConfig: AzureWhisperConfig,
        logger: Logger = PrintLogger(subsystem: "HybridWhisperTranscriber"),
        session: URLSession = .shared
    ) {
        self.recorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "HybridWhisperTranscriber.Mic"))
        self.whisperEngine = WhisperEngine(config: whisperConfig, session: session,
                                           logger: PrintLogger(subsystem: "WhisperEngine"))
        self.logger = logger
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
        _isTranscribing.withLock { $0 }
    }

    public func start(language: Locale) async throws {
        logger.info("start() language: \(language.identifier)")

        if _isTranscribing.withLock({ $0 }) {
            logger.warning("Already transcribing, stopping first")
            await stop()
        }

        recordingLocale = language
        appleHasContent = false

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
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16, macOS 13, *) {
            request.requiresOnDeviceRecognition = false
        }
        recognitionRequest = request

        // 启动录音：buffer 同步喂给 Apple Speech，同时写入 WAV 文件（由 MicrophoneRecorder 负责）
        try await recorder.start { buffer in
            request.append(buffer)
        }

        captureStateSubject.send(.recording)
        _isTranscribing.withLock { $0 = true }
        logger.info("Recording + Apple Speech started")

        // 启动 Apple Speech 识别任务
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty {
                    self.appleHasContent = true
                    self.appleLatestText = text
                }

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
                self.logger.error("Apple Speech error: \(e.domain) \(e.code) \(e.localizedDescription)")
                self.stopRecorder()
            }
        }
    }

    public func stop() async {
        logger.info("stop() called, appleHasContent=\(appleHasContent)")

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

        // 只有 Apple Speech 有内容时才调用 Whisper
        guard hadContent else {
            logger.info("Apple Speech had no content → skipping Whisper")
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        do {
            logger.info("Apple Speech had content → submitting to Whisper")
            let whisperText = try await whisperEngine.transcribe(fileURL: fileURL, language: recordingLocale)
            if merger != nil && !appleSpeechText.isEmpty && appleSpeechText != whisperText {
                logger.info("Merging Apple Speech + Whisper via LLM")
            }
            let finalText = await mergedTranscription(
                appleSpeech: appleSpeechText,
                whisper: whisperText,
                merger: merger
            )
            let result = TranscriptionResult(
                text: finalText, type: .final,
                confidence: nil, timestamp: Date(), locale: recordingLocale
            )
            liveResultSubject.send(result)
            finalResultSubject.send(result)
        } catch {
            logger.error("Whisper error: \(error.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: fileURL)
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
