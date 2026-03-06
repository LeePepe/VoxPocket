import AVFoundation
import Combine
import Foundation
import Observability
import Synchronization

/// Azure OpenAI Whisper 转录协调器（纯批量模式）
///
/// 使用 `MicrophoneRecorder` 采集音频，录音结束后由 `WhisperEngine` 批量转录。
/// 录音期间无实时文字结果；通过 RMS 静音检测实现自动停止。
public final class AzureWhisperTranscriber: NSObject, @unchecked Sendable {

    // MARK: - Dependencies

    fileprivate let recorder: MicrophoneRecorder
    private let whisperEngine: WhisperEngine
    private let config: AzureWhisperConfig

    // MARK: - Publishers

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    // MARK: - State

    private let _isTranscribing = Mutex(false)
    private let logger: Logger
    private var recordingLocale: Locale = Locale(identifier: "zh-Hans")
    private var recordingStartTime: Date?
    private var silenceTask: Task<Void, Never>?

    // MARK: - Sub-services

    private lazy var _audioCaptureService: WhisperAudioCapture = WhisperAudioCapture(transcriber: self)
    private lazy var _speechRecognitionService: WhisperSpeechRecognition = WhisperSpeechRecognition(transcriber: self)

    // MARK: - Init

    public init(
        config: AzureWhisperConfig,
        logger: Logger = PrintLogger(subsystem: "AzureWhisperTranscriber"),
        session: URLSession = .shared
    ) {
        self.config = config
        self.recorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "AzureWhisperTranscriber.Mic"))
        self.whisperEngine = WhisperEngine(config: config, session: session,
                                           logger: PrintLogger(subsystem: "WhisperEngine"))
        self.logger = logger
        super.init()
    }
}

// MARK: - TranscriptionCoordinator

extension AzureWhisperTranscriber: TranscriptionCoordinator {

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
            logger.warning("Already recording, stopping first")
            await stop()
        }

        recordingLocale = language

        let silenceDuration = config.autoStopSilenceDuration
        let silenceThreshold = config.silenceThreshold

        // 录音中监听音量，实现静音自动停止
        try await recorder.start { [weak self] _ in
            guard let self, silenceDuration > 0 else { return }
            let level = self.recorder.audioLevelPublisher  // 仅触发，实际值已通过 audioLevelPublisher 发布
            _ = level  // 静音检测移到 audioLevelPublisher 订阅中
        }

        // 通过 audioLevelPublisher 监听音量做静音检测
        // 注意：此 Task 在 start() 返回后在后台运行
        silenceTask?.cancel()
        if silenceDuration > 0 {
            silenceTask = Task { [weak self] in
                guard let self else { return }
                var silentSince: Date? = nil

                for await level in self.recorder.audioLevelPublisher.values {
                    guard !Task.isCancelled else { return }
                    if level > silenceThreshold {
                        silentSince = nil
                    } else {
                        let now = Date()
                        let start = silentSince ?? { silentSince = now; return now }()
                        if now.timeIntervalSince(start) >= silenceDuration {
                            self.logger.info("Auto-stop: silence \(silenceDuration)s")
                            await self.stop()
                            return
                        }
                    }
                }
            }
        }

        captureStateSubject.send(.recording)
        _isTranscribing.withLock { $0 = true }
        recordingStartTime = Date()
        logger.info("Recording started")
    }

    public func stop() async {
        logger.info("stop() called")

        silenceTask?.cancel()
        silenceTask = nil

        let fileURL = recorder.stop()
        captureStateSubject.send(.idle)
        _isTranscribing.withLock { $0 = false }

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil

        guard let fileURL else {
            logger.warning("No audio file to transcribe")
            return
        }

        guard duration >= 0.5 else {
            logger.warning("Recording too short (\(String(format: "%.2f", duration))s), skipping Whisper")
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        do {
            let text = try await whisperEngine.transcribe(fileURL: fileURL, language: recordingLocale)
            let result = TranscriptionResult(
                text: text, type: .final,
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
}

// MARK: - Internal AudioCaptureService

private final class WhisperAudioCapture: AudioCaptureService, @unchecked Sendable {
    private weak var transcriber: AzureWhisperTranscriber?
    init(transcriber: AzureWhisperTranscriber) { self.transcriber = transcriber }

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

private final class WhisperSpeechRecognition: SpeechRecognitionService, @unchecked Sendable {
    private weak var transcriber: AzureWhisperTranscriber?
    init(transcriber: AzureWhisperTranscriber) { self.transcriber = transcriber }

    var providerType: ASRProviderType { .whisper }

    var resultPublisher: AnyPublisher<TranscriptionResult, Error> {
        transcriber?.liveResultPublisher
            ?? Fail(error: NSError(domain: "", code: -1)).eraseToAnyPublisher()
    }

    func startRecognition(language: Locale) async throws {}
    func stopRecognition() async {}
    func checkAvailability() async -> Bool { true }
    func requestPermission() async -> Bool { true }
    var supportedLanguages: [Locale] { Locale.availableIdentifiers.map { Locale(identifier: $0) } }
}
