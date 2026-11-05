import Foundation
import VoxCore
import Synchronization

#if canImport(WhisperKit)
import WhisperKit
#endif

/// WhisperKit 本地转录协调器
///
/// 流式模式：录音期间持续发布 partial，停止时发布 final。
public final class WhisperKitTranscriber: Sendable {

    // MARK: - Dependencies

    fileprivate let recorder: MicrophoneRecorder
    private let config: LocalWhisperKitConfig
    private let logger: any VoxLogger
    fileprivate let telemetry: any VoxTelemetry
    fileprivate let permissionRequester: @Sendable () async -> Bool
    fileprivate let hasPermissionProvider: @Sendable () -> Bool
    private let engineFactory: @Sendable (LocalWhisperKitConfig, any VoxLogger) -> any LocalWhisperEngine

    // MARK: - Publishers

    let sessionRelay = SpeechSessionRelay()
    private let audioLevelSubject = AsyncValueRelay<Float>(0)
    fileprivate let captureStateSubject = AsyncValueRelay<AudioCaptureState>(.idle)
    private let _modelLoadingStateSubject = AsyncValueRelay<ModelLoadingState>(.idle)

    // MARK: - State

    private let _isTranscribing = Mutex(false)
    private let _engine = Mutex<(any LocalWhisperEngine)?>(nil)
    private let _latestPartialText = Mutex("")
    private let _startedAt = Mutex<Date?>(nil)
    private let locale = Mutex(Locale(identifier: "zh-Hans"))
    private var recordingLocale: Locale {
        get { locale.withLock { $0 } }
        set { locale.withLock { $0 = newValue } }
    }

    /// 后台预加载任务（与录音无关，app 启动时独立运行）
    private let _preloadTask = Mutex<Task<Void, Error>?>(nil)

    // MARK: - Sub-services


    // MARK: - Init


    public init(
        config: LocalWhisperKitConfig,
        logger: any VoxLogger = NoopVoxLogger(),
        recorder: MicrophoneRecorder? = nil,
        telemetry: any VoxTelemetry = NoopVoxTelemetry(),
        storageLocations: VoxStorageLocations
    ) {
        let recorder = recorder ?? MicrophoneRecorder(logger: logger, storageLocations: storageLocations)
        self.engineFactory = { SharedLocalWhisperEngineHandle(config: $0, logger: $1, storageLocations: storageLocations) }
        self.config = config
        self.logger = logger
        self.recorder = recorder
        self.telemetry = telemetry
        self.permissionRequester = { await recorder.requestPermission() }
        self.hasPermissionProvider = { recorder.hasPermission }
        if config.preloadOnStart {
            startBackgroundPreload()
        }
    }

    init(
        config: LocalWhisperKitConfig,
        logger: any VoxLogger,
        recorder: MicrophoneRecorder,
        telemetry: any VoxTelemetry = NoopVoxTelemetry(),
        permissionRequester: (@Sendable () async -> Bool)? = nil,
        hasPermissionProvider: (@Sendable () -> Bool)? = nil,
        engineFactory: @escaping @Sendable (LocalWhisperKitConfig, any VoxLogger) -> any LocalWhisperEngine,
        autoPreload: Bool = false
    ) {
        self.config = config
        self.logger = logger
        self.recorder = recorder
        self.telemetry = telemetry
        self.permissionRequester = permissionRequester ?? { await recorder.requestPermission() }
        self.hasPermissionProvider = hasPermissionProvider ?? { recorder.hasPermission }
        self.engineFactory = engineFactory
        if autoPreload && config.preloadOnStart {
            startBackgroundPreload()
        }
    }

    /// 后台下载并加载模型，与录音流程完全解耦
    @discardableResult
    private func startBackgroundPreload() -> Task<Void, Error>? {
        _preloadTask.withLock { pending in
            if _engine.withLock({ $0 }) != nil { return nil }
            if let pending { return pending }
            _modelLoadingStateSubject.send(.loading)
            let task = Task<Void, Error> { [weak self] in
                guard let self else { return }
                defer { self._preloadTask.withLock { $0 = nil } }
                let startedAt = Date()
                let engine = self.engineFactory(self.config, self.logger)
                do {
                    try await engine.prepare(onProgress: { [weak self] progress in
                        self?._modelLoadingStateSubject.send(.downloading(progress: progress))
                    })
                    self._engine.withLock { $0 = engine }
                    self._modelLoadingStateSubject.send(.ready)
                    self.logger.info("WhisperKit model preloaded and ready")
                    let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    self.telemetry.record(VoxTelemetryEvent(name: "whisper.model.loaded", fields: [.label("model", .source("whisperKit")), .durationMs("load_ms", Double(loadMs))]))
                } catch {
                    self._modelLoadingStateSubject.send(.failed("Model preparation failed"))
                    self.logger.error("WhisperKit model preload failed")
                    self.telemetry.record(VoxTelemetryEvent(name: "whisper.model.load_failed", fields: [.label("model", .source("whisperKit")), .label("error_kind", .reason("model_preparation"))]))
                    throw error
                }
            }
            pending = task
            return task
        }
    }

    private func ensureEngineReady() async throws -> any LocalWhisperEngine {
        if let existing = _engine.withLock({ $0 }) { return existing }
        if let preparation = startBackgroundPreload() { try await preparation.value }
        guard let engine = _engine.withLock({ $0 }) else {
            throw VoxKitError.modelNotReady
        }
        return engine
    }

    private func trackTranscriptionFailure(phase: VoxLabel) {
        telemetry.record(VoxTelemetryEvent(name: "transcription.failed", fields: [
            .label("provider", .provider("whisperkit")), .label("model", .source("whisperKit")),
            .label("phase", phase), .label("error_kind", phase == .step("model_load") ? .reason("model_preparation") : .reason("streaming_start"))
        ]))
    }

    private func acceptLivePartial(_ text: String) -> String? {
        let sanitized = Self.sanitizeLivePartialText(text)
        guard !sanitized.isEmpty else { return nil }

        return _latestPartialText.withLock { latest in
            let current = latest.trimmingCharacters(in: .whitespacesAndNewlines)
            guard sanitized != current else { return nil }

            // 只接受更长或等长但不同的文本，防止 Whisper 回退到更短的 hypothesis 覆盖已有内容
            if sanitized.count < current.count {
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

extension WhisperKitTranscriber: ModelLoadingStateProviding {
    public var modelLoadingState: ModelLoadingState {
        _modelLoadingStateSubject.value
    }

    public func modelLoadingStates() -> AsyncStream<ModelLoadingState> {
        _modelLoadingStateSubject.stream()
    }
}

extension WhisperKitTranscriber: ModelPreloadControlling {
    public func startModelPreloadIfNeeded() {
        startBackgroundPreload()
    }
}

// MARK: - TranscriptionCoordinator

extension WhisperKitTranscriber: SessionDriving {

    public var providerKind: ASRProviderType { .whisper }
    public var supportedLanguages: [Locale] { Locale.availableIdentifiers.map { Locale(identifier: $0) } }
    public var isActive: Bool { isTranscribing }
    public var hasMicrophonePermission: Bool { hasPermissionProvider() }
    public var hasSpeechPermission: Bool { true }
    public func requestMicrophonePermission() async -> Bool { await permissionRequester() }
    public func requestSpeechPermission() async -> Bool { true }
    public func captureStates() -> AsyncStream<AudioCaptureState> { captureStateSubject.stream() }
    public func audioLevels() -> AsyncStream<Float> { audioLevelSubject.stream() }

    public var isTranscribing: Bool {
        _isTranscribing.withLock { $0 }
    }

    public func start(language: Locale) async throws {
        logger.info("start()", fields: [.label("language", .source("locale"))])

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
            trackTranscriptionFailure(phase: .step("model_load"))
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
                    self.sessionRelay.send(.partial(result))
                },
                onAudioLevel: { [weak self] level in
                    self?.audioLevelSubject.send(level)
                }
            )
        } catch {
            trackTranscriptionFailure(phase: .step("stream_start"))
            await stop()
            throw error
        }

        captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
        _isTranscribing.withLock { $0 = true }
        _startedAt.withLock { $0 = Date() }
    }

    public func stop() async {
        logger.info("stop() called")
        defer { sessionRelay.finish() }

        _isTranscribing.withLock { $0 = false }
        let startedAt = _startedAt.withLock { state -> Date? in
            defer { state = nil }
            return state
        }
        captureStateSubject.send(.idle); sessionRelay.send(.state(.idle))
        audioLevelSubject.send(0)

        guard let engine = _engine.withLock({ $0 }) else {
            return
        }

        await engine.stopStreaming()

        // 对全量音频做一次完整转录，捕捉流式解码漏掉的最后 <1s 内容
        // 加 5 秒超时：避免 WhisperKit 多次 temperature fallback 导致 6+ 秒卡顿
        let languageCode = config.languageHint(for: recordingLocale)
        let fullTranscription: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                try? await engine.transcribeAccumulatedAudio(languageCode: languageCode)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }

        let streamingText = _latestPartialText.withLock { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
        // 优先用完整转录（更全），fallback 到流式结果
        let finalText = fullTranscription ?? streamingText
        guard !finalText.isEmpty else { return }

        let result = TranscriptionResult(
            text: finalText,
            type: .final,
            confidence: nil,
            timestamp: Date(),
            locale: recordingLocale
        )
        sessionRelay.send(.partial(result))
        sessionRelay.send(.final(result))

        if let startedAt {
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            telemetry.record(VoxTelemetryEvent(name: "transcription.completed", fields: [.label("provider", .provider("whisperkit")), .label("model", .source("whisperKit")), .durationMs("elapsed_ms", Double(max(elapsedMs, 0))), .double("rtf_rough", 1), .int("text_length", finalText.count)]))
        }
    }

    public func pause() async {
        captureStateSubject.send(.paused); sessionRelay.send(.state(.paused))
        await _engine.withLock { $0 }?.pauseStreaming()
    }

    public func resume() async {
        captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
        await _engine.withLock { $0 }?.resumeStreaming()
    }

}
