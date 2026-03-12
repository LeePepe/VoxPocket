import Combine
import Foundation
import Observability
import Synchronization

#if canImport(WhisperKit)
import WhisperKit
#endif

/// WhisperKit 本地转录协调器
///
/// 流式模式：录音期间持续发布 partial，停止时发布 final。
public final class WhisperKitTranscriber: NSObject, @unchecked Sendable {

    // MARK: - Dependencies

    fileprivate let recorder: MicrophoneRecorder
    private let config: LocalWhisperKitConfig
    private let logger: Logger
    fileprivate let telemetry: TelemetryService
    fileprivate let permissionRequester: @Sendable () async -> Bool
    fileprivate let hasPermissionProvider: @Sendable () -> Bool
    private let engineFactory: @Sendable (LocalWhisperKitConfig, Logger) -> any LocalWhisperEngine

    // MARK: - Publishers

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    // MARK: - State

    private let _isTranscribing = Mutex(false)
    private let _engine = Mutex<(any LocalWhisperEngine)?>(nil)
    private let _latestPartialText = Mutex("")
    private let _startedAt = Mutex<Date?>(nil)
    private var recordingLocale: Locale = Locale(identifier: "zh-Hans")

    /// 后台预加载任务（与录音无关，app 启动时独立运行）
    private let _preloadTask = Mutex<Task<Void, Error>?>(nil)

    // MARK: - Sub-services

    private lazy var _audioCaptureService: WhisperKitAudioCapture = WhisperKitAudioCapture(transcriber: self)
    private lazy var _speechRecognitionService: WhisperKitSpeechRecognition = WhisperKitSpeechRecognition(transcriber: self)

    // MARK: - Init

    public convenience override init() {
        self.init(config: .default)
    }

    public init(
        config: LocalWhisperKitConfig,
        logger: Logger = PrintLogger(subsystem: "WhisperKitTranscriber"),
        recorder: MicrophoneRecorder = MicrophoneRecorder(logger: PrintLogger(subsystem: "WhisperKitTranscriber.Mic")),
        telemetry: TelemetryService = NoopTelemetryService()
    ) {
        self.engineFactory = { LocalWhisperKitEngine(config: $0, logger: $1) }
        self.config = config
        self.logger = logger
        self.recorder = recorder
        self.telemetry = telemetry
        self.permissionRequester = { await recorder.requestPermission() }
        self.hasPermissionProvider = { recorder.hasPermission }
        super.init()
        if config.preloadOnStart {
            startBackgroundPreload()
        }
    }

    init(
        config: LocalWhisperKitConfig,
        logger: Logger,
        recorder: MicrophoneRecorder,
        telemetry: TelemetryService = NoopTelemetryService(),
        permissionRequester: (@Sendable () async -> Bool)? = nil,
        hasPermissionProvider: (@Sendable () -> Bool)? = nil,
        engineFactory: @escaping @Sendable (LocalWhisperKitConfig, Logger) -> any LocalWhisperEngine,
        autoPreload: Bool = false
    ) {
        self.config = config
        self.logger = logger
        self.recorder = recorder
        self.telemetry = telemetry
        self.permissionRequester = permissionRequester ?? { await recorder.requestPermission() }
        self.hasPermissionProvider = hasPermissionProvider ?? { recorder.hasPermission }
        self.engineFactory = engineFactory
        super.init()
        if autoPreload && config.preloadOnStart {
            startBackgroundPreload()
        }
    }

    /// 后台下载并加载模型，与录音流程完全解耦
    private func startBackgroundPreload() {
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            let engine = self.engineFactory(self.config, self.logger)
            do {
                try await engine.prepare()
                self._engine.withLock { $0 = engine }
                self.logger.info("WhisperKit model preloaded and ready")
                let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                self.telemetry.track(
                    name: TelemetryEventName.whisperModelLoaded.rawValue,
                    properties: [
                        "model": self.config.model,
                        "load_ms": String(loadMs)
                    ]
                )
            } catch {
                self.telemetry.track(
                    name: TelemetryEventName.whisperModelLoadFailed.rawValue,
                    properties: [
                        "model": self.config.model,
                        "reason": String(describing: error)
                    ]
                )
                throw error
            }
        }
        _preloadTask.withLock { $0 = task }
    }

    private func ensureEngineReady() async throws -> any LocalWhisperEngine {
        if let existing = _engine.withLock({ $0 }) {
            return existing
        }

        if _preloadTask.withLock({ $0 }) == nil {
            startBackgroundPreload()
        }

        guard let preloadTask = _preloadTask.withLock({ $0 }) else {
            throw NSError(
                domain: "WhisperKitTranscriber",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "WhisperKit 模型预加载任务不存在"]
            )
        }
        try await preloadTask.value

        guard let engine = _engine.withLock({ $0 }) else {
            throw NSError(
                domain: "WhisperKitTranscriber",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "WhisperKit 模型加载失败"]
            )
        }
        return engine
    }

    private func trackTranscriptionFailure(_ error: Error, phase: String) {
        telemetry.track(
            name: TelemetryEventName.transcriptionFailed.rawValue,
            properties: [
                "provider": "whisperkit",
                "model": config.model,
                "phase": phase,
                "reason": String(describing: error)
            ]
        )
    }
}

// MARK: - TranscriptionCoordinator

extension WhisperKitTranscriber: TranscriptionCoordinator {

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
        logger.info("start() language: \(language.identifier)")

        if _isTranscribing.withLock({ $0 }) {
            logger.warning("Already transcribing, stopping first")
            await stop()
        }

        let granted = await permissionRequester()
        guard granted else {
            throw NSError(
                domain: "WhisperKitTranscriber", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "麦克风权限未授权"]
            )
        }

        let engine: any LocalWhisperEngine
        do {
            engine = try await ensureEngineReady()
        } catch {
            trackTranscriptionFailure(error, phase: "model_load")
            await stop()
            throw error
        }

        recordingLocale = language
        _latestPartialText.withLock { $0 = "" }

        let languageCode = config.languageHint(for: language)

        do {
            try await engine.startStreaming(
                languageCode: languageCode,
                onPartial: { [weak self] text in
                    guard let self else { return }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != "Waiting for speech..." else { return }
                    self._latestPartialText.withLock { $0 = trimmed }
                    let result = TranscriptionResult(
                        text: trimmed,
                        type: .partial,
                        confidence: nil,
                        timestamp: Date(),
                        locale: self.recordingLocale
                    )
                    self.liveResultSubject.send(result)
                },
                onAudioLevel: { [weak self] level in
                    self?.audioLevelSubject.send(level)
                }
            )
        } catch {
            trackTranscriptionFailure(error, phase: "stream_start")
            await stop()
            throw error
        }

        captureStateSubject.send(.recording)
        _isTranscribing.withLock { $0 = true }
        _startedAt.withLock { $0 = Date() }
    }

    public func stop() async {
        logger.info("stop() called")

        _isTranscribing.withLock { $0 = false }
        let startedAt = _startedAt.withLock { state -> Date? in
            defer { state = nil }
            return state
        }
        captureStateSubject.send(.idle)
        audioLevelSubject.send(0)

        guard let engine = _engine.withLock({ $0 }) else {
            return
        }

        await engine.stopStreaming()

        let finalText = _latestPartialText.withLock { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return }

        let result = TranscriptionResult(
            text: finalText,
            type: .final,
            confidence: nil,
            timestamp: Date(),
            locale: recordingLocale
        )
        liveResultSubject.send(result)
        finalResultSubject.send(result)

        if let startedAt {
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            telemetry.track(
                name: TelemetryEventName.transcriptionCompleted.rawValue,
                properties: [
                    "provider": "whisperkit",
                    "model": config.model,
                    "elapsed_ms": String(max(elapsedMs, 0)),
                    "rtf_rough": "1.0",
                    "text_length": String(finalText.count)
                ]
            )
        }
    }

    public func pause() {
        captureStateSubject.send(.paused)
        Task { [weak self] in
            guard let self, let engine = self._engine.withLock({ $0 }) else { return }
            await engine.pauseStreaming()
        }
    }

    public func resume() {
        captureStateSubject.send(.recording)
        Task { [weak self] in
            guard let self, let engine = self._engine.withLock({ $0 }) else { return }
            await engine.resumeStreaming()
        }
    }

}

// MARK: - Internal AudioCaptureService

private final class WhisperKitAudioCapture: AudioCaptureService, @unchecked Sendable {
    private weak var transcriber: WhisperKitTranscriber?
    init(transcriber: WhisperKitTranscriber) { self.transcriber = transcriber }

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
    func requestPermission() async -> Bool { await transcriber?.permissionRequester() ?? false }
    var hasPermission: Bool { transcriber?.hasPermissionProvider() ?? false }
}

// MARK: - Internal SpeechRecognitionService

private final class WhisperKitSpeechRecognition: SpeechRecognitionService, @unchecked Sendable {
    private weak var transcriber: WhisperKitTranscriber?
    init(transcriber: WhisperKitTranscriber) { self.transcriber = transcriber }

    var providerType: ASRProviderType { .whisper }

    var resultPublisher: AnyPublisher<TranscriptionResult, Error> {
        transcriber?.liveResultPublisher
            ?? Fail(error: NSError(domain: "", code: -1)).eraseToAnyPublisher()
    }

    func startRecognition(language: Locale) async throws {}
    func stopRecognition() async {}
    func checkAvailability() async -> Bool { true }
    func requestPermission() async -> Bool { await transcriber?.permissionRequester() ?? false }
    var supportedLanguages: [Locale] { Locale.availableIdentifiers.map { Locale(identifier: $0) } }
}

// MARK: - Engine abstraction

protocol LocalWhisperEngine: Sendable {
    func prepare() async throws
    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws
    func stopStreaming() async
    func pauseStreaming() async
    func resumeStreaming() async
}

private actor LocalWhisperKitEngine: LocalWhisperEngine {
    private let config: LocalWhisperKitConfig
    private let logger: Logger

#if canImport(WhisperKit)
    private var pipeline: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamTask: Task<Void, Error>?
#endif

    init(config: LocalWhisperKitConfig, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    func prepare() async throws {
#if canImport(WhisperKit)
        if pipeline != nil {
            return
        }

        logger.info("Downloading/locating WhisperKit model: \(config.model)")
        let modelFolder = try await WhisperKit.download(
            variant: config.model,
            progressCallback: { [logger] progress in
                let pct = Int(progress.fractionCompleted * 100)
                let completed = progress.completedUnitCount
                let total = progress.totalUnitCount
                if total > 0 {
                    logger.info("WhisperKit model download: \(pct)% (\(completed)/\(total) bytes)")
                } else {
                    logger.info("WhisperKit model download: \(pct)%")
                }
            }
        )
        logger.info("Model ready at: \(modelFolder.path)")

        let whisperConfig = WhisperKitConfig(modelFolder: modelFolder.path)
        pipeline = try await WhisperKit(whisperConfig)
        logger.info("WhisperKit pipeline loaded successfully")
#else
        throw NSError(
            domain: "WhisperKitTranscriber", code: -100,
            userInfo: [NSLocalizedDescriptionKey: "WhisperKit module unavailable in current build"]
        )
#endif
    }

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
#if canImport(WhisperKit)
        if streamTask != nil {
            return
        }

        try await prepare()
        guard let pipeline else {
            throw NSError(
                domain: "WhisperKitTranscriber", code: -101,
                userInfo: [NSLocalizedDescriptionKey: "WhisperKit pipeline not initialized"]
            )
        }

        var options = DecodingOptions()
        options.language = languageCode

        nonisolated(unsafe) let audioEncoder = pipeline.audioEncoder
        nonisolated(unsafe) let featureExtractor = pipeline.featureExtractor
        nonisolated(unsafe) let segmentSeeker = pipeline.segmentSeeker
        nonisolated(unsafe) let textDecoder = pipeline.textDecoder
        nonisolated(unsafe) let audioProcessor = pipeline.audioProcessor
        let tokenizer = try pipeline.tokenizerRequired()
        nonisolated(unsafe) let tokenizerRef = tokenizer

        let transcriber = AudioStreamTranscriber(
            audioEncoder: audioEncoder,
            featureExtractor: featureExtractor,
            segmentSeeker: segmentSeeker,
            textDecoder: textDecoder,
            tokenizer: tokenizerRef,
            audioProcessor: audioProcessor,
            decodingOptions: options,
            stateChangeCallback: { _, newState in
                let mergedText = LocalWhisperKitEngine.composeStreamText(from: newState)
                onPartial(mergedText)
                let level = newState.bufferEnergy.last ?? 0
                onAudioLevel(level)
            }
        )

        streamTranscriber = transcriber
        streamTask = Task {
            try await transcriber.startStreamTranscription()
        }
#else
        _ = languageCode
        _ = onPartial
        _ = onAudioLevel
        throw NSError(
            domain: "WhisperKitTranscriber", code: -100,
            userInfo: [NSLocalizedDescriptionKey: "WhisperKit module unavailable in current build"]
        )
#endif
    }

    func stopStreaming() async {
#if canImport(WhisperKit)
        if let streamTranscriber {
            await streamTranscriber.stopStreamTranscription()
        }
        if let streamTask {
            _ = try? await streamTask.value
        }
        streamTask = nil
        streamTranscriber = nil
#endif
    }

    func pauseStreaming() async {
#if canImport(WhisperKit)
        pipeline?.audioProcessor.pauseRecording()
#endif
    }

    func resumeStreaming() async {
#if canImport(WhisperKit)
        _ = try? pipeline?.audioProcessor.resumeRecordingLive(inputDeviceID: nil, callback: nil)
#endif
    }

#if canImport(WhisperKit)
    private nonisolated static func composeStreamText(from state: AudioStreamTranscriber.State) -> String {
        let confirmed = state.confirmedSegments.map(\.text).joined(separator: " ")
        let current = state.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = [confirmed, current]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        return stripWhisperTokens(from: merged.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 剥离 Whisper 特殊 token，如 <|startoftranscript|>、<|zh|>、<|0.00|> 等
    private nonisolated static func stripWhisperTokens(from text: String) -> String {
        let pattern = try? NSRegularExpression(pattern: "<\\|[^|]+\\|>")
        let range = NSRange(text.startIndex..., in: text)
        let stripped = pattern?.stringByReplacingMatches(in: text, range: range, withTemplate: "") ?? text
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
#endif
}

#if canImport(WhisperKit)
private extension WhisperKit {
    func tokenizerRequired() throws -> any WhisperTokenizer {
        if let tokenizer {
            return tokenizer
        }
        throw NSError(
            domain: "WhisperKitTranscriber", code: -103,
            userInfo: [NSLocalizedDescriptionKey: "WhisperKit tokenizer unavailable"]
        )
    }
}
#endif
