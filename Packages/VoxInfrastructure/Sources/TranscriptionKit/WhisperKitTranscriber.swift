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
    private let _modelLoadingStateSubject = CurrentValueSubject<ModelLoadingState, Never>(.idle)

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
        self.engineFactory = { SharedLocalWhisperEngineHandle(config: $0, logger: $1) }
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
        if _engine.withLock({ $0 }) != nil {
            _modelLoadingStateSubject.send(.ready)
            return
        }
        if _preloadTask.withLock({ $0 }) != nil {
            return
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            defer {
                self._preloadTask.withLock { $0 = nil }
            }
            let startedAt = Date()
            let engine = self.engineFactory(self.config, self.logger)
            do {
                try await engine.prepare(onProgress: { [weak self] progress in
                    self?._modelLoadingStateSubject.send(.downloading(progress: progress))
                })
                self._modelLoadingStateSubject.send(.ready)
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
                self._modelLoadingStateSubject.send(.failed(error.localizedDescription))
                self.logger.error("WhisperKit model preload failed: \(error.localizedDescription)")
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
        _modelLoadingStateSubject.send(.loading)
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

    private func acceptLivePartial(_ text: String) -> String? {
        let sanitized = Self.sanitizeLivePartialText(text)
        guard !sanitized.isEmpty else { return nil }

        return _latestPartialText.withLock { latest in
            let current = latest.trimmingCharacters(in: .whitespacesAndNewlines)
            guard sanitized != current else { return nil }

            // Whisper 在停顿时会回退到更短的 hypothesis；不要让它覆盖更完整的文本。
            if !current.isEmpty, current.hasPrefix(sanitized) {
                return nil
            }

            latest = sanitized
            return sanitized
        }
    }

    private static func sanitizeLivePartialText(_ text: String) -> String {
        let withoutPlaceholder = text
            .replacingOccurrences(of: "Waiting for speech...", with: " ")
            .replacingOccurrences(of: "Realtime transcription has started", with: " ")
            .replacingOccurrences(of: "Realtime transcription has ended", with: " ")

        let collapsedWhitespace = withoutPlaceholder
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ModelLoadingObservable

extension WhisperKitTranscriber: ModelLoadingObservable {
    public var modelLoadingState: ModelLoadingState {
        _modelLoadingStateSubject.value
    }

    public var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> {
        _modelLoadingStateSubject.eraseToAnyPublisher()
    }
}

extension WhisperKitTranscriber: ModelPreloadControlling {
    public func startModelPreloadIfNeeded() {
        startBackgroundPreload()
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
                    // 停止后可能仍有 in-flight partial 到达，忽略避免污染结果
                    guard self._isTranscribing.withLock({ $0 }) else { return }
                    guard let acceptedText = self.acceptLivePartial(text) else { return }
                    let result = TranscriptionResult(
                        text: acceptedText,
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
    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws
    func startStreaming(

        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws
    func stopStreaming() async
    func pauseStreaming() async
    func resumeStreaming() async
}

enum LocalWhisperRawOutputLogger {
    static func log(_ rawText: String, logger: Logger) {
        let normalized = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        logger.debug("Local Whisper raw output: \(normalized)")
    }
}

private actor SharedLocalWhisperEnginePool {
    static let shared = SharedLocalWhisperEnginePool()

    private var engines: [String: any LocalWhisperEngine] = [:]

    func engine(for config: LocalWhisperKitConfig, logger: Logger) -> any LocalWhisperEngine {
        let key = config.resolvedModelVariant
        if let existing = engines[key] {
            return existing
        }

        let engine = LocalWhisperKitEngine(config: config, logger: logger)
        engines[key] = engine
        return engine
    }
}

private final class SharedLocalWhisperEngineHandle: LocalWhisperEngine {
    private let config: LocalWhisperKitConfig
    private let logger: Logger

    init(config: LocalWhisperKitConfig, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    private func engine() async -> any LocalWhisperEngine {
        await SharedLocalWhisperEnginePool.shared.engine(for: config, logger: logger)
    }

    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        let engine = await engine()
        try await engine.prepare(onProgress: onProgress)
    }

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        let engine = await engine()
        try await engine.startStreaming(
            languageCode: languageCode,
            onPartial: onPartial,
            onAudioLevel: onAudioLevel
        )
    }

    func stopStreaming() async {
        let engine = await engine()
        await engine.stopStreaming()
    }

    func pauseStreaming() async {
        let engine = await engine()
        await engine.pauseStreaming()
    }

    func resumeStreaming() async {
        let engine = await engine()
        await engine.resumeStreaming()
    }
}

private actor LocalWhisperKitEngine: LocalWhisperEngine {
    private let config: LocalWhisperKitConfig
    private let logger: Logger

#if canImport(WhisperKit)
    private var pipeline: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamTask: Task<Void, Error>?
    private var prepareTask: Task<Void, Error>?
#endif

    init(config: LocalWhisperKitConfig, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    private static func dedicatedDownloadBase() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("VoxPocketWhisperKitHub", isDirectory: true)
    }

    private static func isRecoverableSnapshotError(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains(".incomplete")
            || text.contains("couldn’t be moved")
            || text.contains("couldn't be moved")
    }

    private static func resetCorruptedCache(downloadBase: URL?, modelFolder: URL?) {
        let fileManager = FileManager.default
        if let modelFolder {
            try? fileManager.removeItem(at: modelFolder)
        }
        if let downloadBase {
            try? fileManager.removeItem(at: downloadBase)
            try? fileManager.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        }
        for cachePath in huggingFaceWhisperKitRepoCacheCandidates() {
            try? fileManager.removeItem(at: cachePath)
        }
    }

    private static func huggingFaceWhisperKitRepoCacheCandidates() -> [URL] {
        let fileManager = FileManager.default
        var roots: [URL] = []

        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            roots.append(caches.appendingPathComponent("huggingface/hub", isDirectory: true))
        }

        let home = fileManager.homeDirectoryForCurrentUser
        roots.append(home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true))

        return roots.map {
            $0.appendingPathComponent("models--argmaxinc--whisperkit-coreml", isDirectory: true)
        }
    }

    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
#if canImport(WhisperKit)
        if pipeline != nil {
            return
        }

        if let prepareTask {
            try await prepareTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            try await self.performPrepare(onProgress: onProgress)
        }
        prepareTask = task
        defer { prepareTask = nil }

        try await task.value
#else
        _ = onProgress
        throw NSError(
            domain: "WhisperKitTranscriber", code: -100,
            userInfo: [NSLocalizedDescriptionKey: "WhisperKit module unavailable in current build"]
        )
#endif
    }

#if canImport(WhisperKit)
    private func performPrepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        let modelVariant = config.resolvedModelVariant
        logger.info("Downloading/locating WhisperKit model: \(config.model)")
        if modelVariant != config.model {
            logger.info("Resolved WhisperKit variant: \(modelVariant)")
        }
        let downloadBase = Self.dedicatedDownloadBase()
        if let downloadBase {
            try? FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        }

        let downloadModel: () async throws -> URL = { [logger = self.logger] in
            try await WhisperKit.download(
                variant: modelVariant,
                downloadBase: downloadBase,
                progressCallback: { progress in
                    let pct = Int(progress.fractionCompleted * 100)
                    let completed = progress.completedUnitCount
                    let total = progress.totalUnitCount
                    if total > 0 {
                        logger.info("WhisperKit model download: \(pct)% (\(completed)/\(total) bytes)")
                    } else {
                        logger.info("WhisperKit model download: \(pct)%")
                    }
                    onProgress?(progress.fractionCompleted)
                }
            )
        }

        var lastModelFolder: URL?
        let initializePipeline: () async throws -> WhisperKit = { [self] in
            let modelFolder = try await downloadModel()
            lastModelFolder = modelFolder
            self.logger.info("Model ready at: \(modelFolder.path)")
            onProgress?(1.0)

            self.logger.info("Loading WhisperKit pipeline from model folder...")
            let whisperConfig = WhisperKitConfig(modelFolder: modelFolder.path)
            return try await WhisperKit(whisperConfig)
        }

        do {
            pipeline = try await initializePipeline()
        } catch {
            guard Self.isRecoverableSnapshotError(error) else { throw error }
            logger.warning("WhisperKit cache appears corrupted. Clearing cache and retrying once.")
            Self.resetCorruptedCache(downloadBase: downloadBase, modelFolder: lastModelFolder)
            pipeline = try await initializePipeline()
        }
        logger.info("WhisperKit pipeline loaded successfully")
    }
#endif

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
#if canImport(WhisperKit)
        if streamTask != nil {
            return
        }

        try await prepare(onProgress: nil)
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

        // 跟踪峰值已确认文本：按字符数比较，只增不减，防止 WhisperKit 窗口切换时丢失历史片段
        nonisolated(unsafe) var peakConfirmedText = ""

        let transcriber = AudioStreamTranscriber(
            audioEncoder: audioEncoder,
            featureExtractor: featureExtractor,
            segmentSeeker: segmentSeeker,
            textDecoder: textDecoder,
            tokenizer: tokenizerRef,
            audioProcessor: audioProcessor,
            decodingOptions: options,
            stateChangeCallback: { _, newState in
                // 用字符数做比较：新的确认文本更长才更新，防止窗口滑动后丢失旧内容
                let newConfirmedText = newState.confirmedSegments.map(\.text).joined(separator: " ")
                if newConfirmedText.count > peakConfirmedText.count {
                    peakConfirmedText = newConfirmedText
                }
                // 只使用已确认的文本，不混入 hypothesis，避免跳动和回退
                guard !peakConfirmedText.isEmpty else { return }
                onPartial(LocalWhisperKitEngine.cleanStreamText(fromRaw: peakConfirmedText))
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
        // Cancel the task but do NOT await its value:
        // WhisperKit may continue decoding buffered audio for ~2s after
        // stopStreamTranscription(), and awaiting here blocks the UI for that
        // duration. Late onPartial callbacks after stop are harmless because
        // WhisperKitTranscriber.start()'s onPartial closure guards on
        // _isTranscribing before forwarding results.
        streamTask?.cancel()
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
    private nonisolated static func cleanStreamText(fromRaw rawText: String) -> String {
        stripWhisperTokens(from: rawText)
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
