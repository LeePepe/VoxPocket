import AVFoundation
import Combine
import Foundation
import LokiKit
import Speech
import Synchronization

/// Apple Speech Framework 转录协调器
///
/// 使用 `MicrophoneRecorder` 采集音频，`SFSpeechRecognizer` 实时识别文字。
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

    private let _isTranscribing = Mutex(false)
    private let logger: Logger

    // MARK: - Sub-services

    private lazy var _audioCaptureService: AppleAudioCapture = AppleAudioCapture(transcriber: self)
    private lazy var _speechRecognitionService: AppleSpeechRecognition = AppleSpeechRecognition(transcriber: self)

    // MARK: - Init

    public override init() {
        self.recorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "AppleSpeechTranscriber.Mic"))
        self.logger = PrintLogger(subsystem: "AppleSpeechTranscriber")
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        logger.debug("init with default locale zh-Hans")
    }

    public init(locale: Locale, logger: Logger = PrintLogger(subsystem: "AppleSpeechTranscriber")) {
        self.recorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "AppleSpeechTranscriber.Mic"))
        self.logger = logger
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        logger.debug("init with locale: \(locale.identifier)")
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
        _isTranscribing.withLock { $0 }
    }

    public func start(language: Locale) async throws {
        logger.info("start() language: \(language.identifier)")

        if _isTranscribing.withLock({ $0 }) {
            logger.warning("Already transcribing, stopping first")
            await stop()
        }

        // 请求语音识别权限
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else {
            throw NSError(domain: "AppleSpeechTranscriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "语音识别权限未授权"])
        }

        // 更新 recognizer locale
        if speechRecognizer?.locale.language.languageCode != language.language.languageCode {
            speechRecognizer = SFSpeechRecognizer(locale: language)
        }
        guard let speechRecognizer else {
            throw NSError(domain: "AppleSpeechTranscriber", code: -2,
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

        // 启动录音，将 buffer 实时送给识别请求
        try await recorder.start { buffer in
            request.append(buffer)
        }

        captureStateSubject.send(.recording)
        _isTranscribing.withLock { $0 = true }
        logger.info("Recording + recognition started")

        // 启动识别任务
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

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
                self.liveResultSubject.send(transcriptionResult)
                if result.isFinal {
                    self.finalResultSubject.send(transcriptionResult)
                    // 任务自然完成，清理 task
                    self.recognitionTask = nil
                }
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

    public func stop() async {
        logger.info("stop() called")
        // 先停录音，再告知识别器音频结束
        // 不立即 cancel recognitionTask，让其自然完成并返回 isFinal 结果
        recorder.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        captureStateSubject.send(.idle)
        _isTranscribing.withLock { $0 = false }
        logger.debug("stop() done")
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
