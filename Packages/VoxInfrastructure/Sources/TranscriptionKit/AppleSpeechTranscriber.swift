import AVFoundation
import Combine
import Foundation
import Observability
import Speech
import Synchronization

/// Apple Speech Framework 转录协调器
///
/// 整合 AVAudioEngine（音频采集）和 SFSpeechRecognizer（语音识别），
/// 实现 `TranscriptionCoordinator` 协议。
public final class AppleSpeechTranscriber: NSObject, @unchecked Sendable {

    // MARK: - Internal state

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    private let _isTranscribing = Mutex(false)
    private let logger: Logger
    private var tapBufferCount = 0

    // MARK: - Lazy sub-services

    private lazy var _audioCaptureService: InternalAudioCapture = InternalAudioCapture(transcriber: self)
    private lazy var _speechRecognitionService: InternalSpeechRecognition = InternalSpeechRecognition(transcriber: self)

    // MARK: - Init

    public override init() {
        self.logger = PrintLogger(subsystem: "AppleSpeechTranscriber")
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        logger.debug("init with default locale zh-Hans")
    }

    public init(locale: Locale, logger: Logger = PrintLogger(subsystem: "AppleSpeechTranscriber")) {
        self.logger = logger
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        self.logger.debug("init with locale: \(locale.identifier)")
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
        audioLevelSubject.eraseToAnyPublisher()
    }

    public var isTranscribing: Bool {
        _isTranscribing.withLock { $0 }
    }

    public func start(language: Locale) async throws {
        logger.info("start() called, language: \(language.identifier)")

        // Re-entrancy guard: prevent calling start() while already transcribing
        let alreadyTranscribing = _isTranscribing.withLock { $0 }
        if alreadyTranscribing {
            logger.warning("start() called while already transcribing, stopping previous session first")
            await stop()
        }

        guard let speechRecognizer else {
            logger.error("SFSpeechRecognizer 不可用")
            throw NSError(domain: "AppleSpeechTranscriber", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer 不可用"])
        }
        logger.debug("speechRecognizer available, locale: \(speechRecognizer.locale.identifier)")

        // 请求权限
        logger.debug("Requesting speech authorization...")
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [logger] status in
                logger.debug("Speech authorization status: \(status.rawValue)")
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else {
            logger.error("语音识别权限未授权")
            throw NSError(domain: "AppleSpeechTranscriber", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "语音识别权限未授权"])
        }
        logger.info("Speech authorization granted")

        // 请求麦克风权限
        #if os(iOS)
        logger.debug("Configuring audio session (iOS)...")
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        logger.info("Audio session configured")
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.debug("mic status: \(status)")
        let desc = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription")
        logger.debug("mic usage desc: \(desc as Any)")
        logger.debug("Requesting microphone permission (macOS)...")
        let micAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        logger.debug("Microphone authorization: \(micAuthorized)")
        guard micAuthorized else {
            logger.error("麦克风权限未授权")
            throw NSError(domain: "AppleSpeechTranscriber", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "麦克风权限未授权"])
        }
        logger.info("Microphone permission granted")
        #endif

        // 更新 recognizer locale（使用 language code 比较，避免 zh-Hans vs zh-CN 规范化差异）
        if speechRecognizer.locale.language.languageCode != language.language.languageCode {
            logger.info("Updating recognizer locale from \(speechRecognizer.locale.identifier) to \(language.identifier)")
            self.speechRecognizer = SFSpeechRecognizer(locale: language)
        } else {
            logger.debug("Recognizer locale unchanged (\(speechRecognizer.locale.identifier) matches \(language.identifier))")
        }

        // 停止之前的任务
        if recognitionTask != nil {
            logger.debug("Cancelling previous recognition task")
        }
        recognitionTask?.finish()
        recognitionTask = nil

        // 创建识别请求
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // iOS 16+ / macOS 13+ 支持设备端识别
        if #available(iOS 16, macOS 13, *) {
            request.requiresOnDeviceRecognition = false
        }
        self.recognitionRequest = request
        logger.debug("Recognition request created")

        // 安装音频 tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        logger.debug("Input node format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")

        // 防御性清理：如果已有 tap 存在，先移除（防止 installTap 崩溃）
        // 这可能发生在 stopInternal() 未完成或异常情况下
        if audioEngine.isRunning {
            logger.debug("Audio engine is running, stopping and removing existing tap before reinstalling")
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
        } else {
            // 即使引擎未运行，也尝试移除可能存在的 tap（防御性编程）
            // removeTap 在没有 tap 时是安全的（不会崩溃）
            inputNode.removeTap(onBus: 0)
            logger.debug("Removed any existing tap (defensive cleanup)")
        }

        tapBufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.tapBufferCount += 1
            if self.tapBufferCount <= 3 {
                self.logger.debug("Audio tap buffer #\(self.tapBufferCount): frameLength=\(buffer.frameLength), format=\(buffer.format.sampleRate)Hz")
            }
            request.append(buffer)
            // 计算音频电平 (RMS)
            let level = self.calculateRMSLevel(buffer: buffer)
            if self.tapBufferCount <= 3 {
                self.logger.debug("Audio level: \(level)")
            }
            self.audioLevelSubject.send(level)
        }
        logger.debug("Audio tap installed on input node")

        // 启动音频引擎
        audioEngine.prepare()
        logger.debug("Audio engine prepared, starting...")
        try audioEngine.start()
        logger.info("Audio engine started, isRunning: \(audioEngine.isRunning)")

        captureStateSubject.send(.recording)
        _isTranscribing.withLock { $0 = true }
        logger.info("State set to recording, isTranscribing = true")

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

                self.logger.debug("Result received - isFinal: \(result.isFinal), text: \(result.bestTranscription.formattedString)")
                self.liveResultSubject.send(transcriptionResult)

                if result.isFinal {
                    self.finalResultSubject.send(transcriptionResult)
                    self.logger.info("Final result sent")
                }
            }

            if let error {
                let nsError = error as NSError
                self.logger.error("Recognition error: domain=\(nsError.domain), code=\(nsError.code), desc=\(nsError.localizedDescription)")
                // 不发送 completion，避免 PassthroughSubject 永久终止。
                // Subject 是单例级别的长生命周期对象，一旦 complete 后续录音都无法接收事件。
                self.stopInternal()
            }
        }
        logger.info("Recognition task started")
    }

    public func stop() async {
        logger.info("stop() called")
        // 结束识别请求，触发 isFinal 结果
        recognitionRequest?.endAudio()
        stopInternal()
    }

    public func pause() {
        logger.info("pause() called")
        audioEngine.pause()
        captureStateSubject.send(.paused)
    }

    public func resume() {
        logger.info("resume() called")
        try? audioEngine.start()
        captureStateSubject.send(.recording)
        logger.debug("Audio engine isRunning after resume: \(audioEngine.isRunning)")
    }

    // MARK: - Private

    private func stopInternal() {
        logger.info("stopInternal() called")
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        captureStateSubject.send(.idle)
        audioLevelSubject.send(0)

        _isTranscribing.withLock { $0 = false }
        logger.debug("stopInternal() completed, isTranscribing = false")
    }

    private func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrtf(sum / Float(frameLength))
        // 归一化到 0.0 - 1.0（dB 映射）
        let avgPower = 20 * log10f(max(rms, 0.000001))
        let minDb: Float = -80
        let normalized = max(0, (avgPower - minDb) / (-minDb))
        return min(1, normalized)
    }
}

// MARK: - Internal AudioCaptureService wrapper

private final class InternalAudioCapture: AudioCaptureService, @unchecked Sendable {
    private weak var transcriber: AppleSpeechTranscriber?

    init(transcriber: AppleSpeechTranscriber) {
        self.transcriber = transcriber
    }

    var state: AudioCaptureState {
        transcriber?.captureStateSubject.value ?? .idle
    }

    var statePublisher: AnyPublisher<AudioCaptureState, Never> {
        transcriber?.captureStateSubject.eraseToAnyPublisher()
            ?? Just(.idle).eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        transcriber?.audioLevelPublisher
            ?? Just(0).eraseToAnyPublisher()
    }

    func startCapture() async throws {
        // Capture 由 coordinator.start() 统一管理
    }

    func stopCapture() async {
        // Capture 由 coordinator.stop() 统一管理
    }

    func pauseCapture() {
        transcriber?.pause()
    }

    func resumeCapture() {
        transcriber?.resume()
    }

    func requestPermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    var hasPermission: Bool {
        #if os(iOS)
        return AVAudioSession.sharedInstance().recordPermission == .granted
        #else
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif
    }
}

// MARK: - Internal SpeechRecognitionService wrapper

private final class InternalSpeechRecognition: SpeechRecognitionService, @unchecked Sendable {
    private weak var transcriber: AppleSpeechTranscriber?

    init(transcriber: AppleSpeechTranscriber) {
        self.transcriber = transcriber
    }

    var providerType: ASRProviderType { .apple }

    var resultPublisher: AnyPublisher<TranscriptionResult, Error> {
        transcriber?.liveResultPublisher
            ?? Fail(error: NSError(domain: "", code: -1)).eraseToAnyPublisher()
    }

    func startRecognition(language: Locale) async throws {
        // Recognition 由 coordinator.start() 统一管理
    }

    func stopRecognition() async {
        // Recognition 由 coordinator.stop() 统一管理
    }

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

    var supportedLanguages: [Locale] {
        SFSpeechRecognizer.supportedLocales().map { $0 }
    }
}
