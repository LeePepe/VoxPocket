import AVFoundation
import Foundation
import VoxCore
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

    let sessionRelay = SpeechSessionRelay()
    fileprivate let captureStateSubject = AsyncValueRelay<AudioCaptureState>(.idle)

    // MARK: - State

    private let _isTranscribing = Mutex(false)
    private let temporaryAudioStore: TemporaryAudioStore
    private let logger: any VoxLogger
    private var recordingLocale: Locale = Locale(identifier: "zh-Hans")
    private var recordingStartTime: Date?
    private var silenceTask: Task<Void, Never>?

    // MARK: - Sub-services


    // MARK: - Init

    public init(
        config: AzureWhisperConfig,
        logger: any VoxLogger = NoopVoxLogger(),
        session: URLSession = .shared,
        storageLocations: VoxStorageLocations
    ) {
        self.temporaryAudioStore = TemporaryAudioStore(storageLocations: storageLocations)
        self.config = config
        self.recorder = MicrophoneRecorder(logger: logger, storageLocations: storageLocations)
        self.whisperEngine = WhisperEngine(config: config, session: session,
                                           logger: logger, storageLocations: storageLocations)
        self.logger = logger
        super.init()
    }
}

// MARK: - TranscriptionCoordinator

extension AzureWhisperTranscriber: SessionDriving {


    public var providerKind: ASRProviderType { .whisper }
    public var supportedLanguages: [Locale] { Locale.availableIdentifiers.map { Locale(identifier: $0) } }
    public var isActive: Bool { isTranscribing }
    public var hasMicrophonePermission: Bool { recorder.hasPermission }
    public var hasSpeechPermission: Bool { true }
    public func requestMicrophonePermission() async -> Bool { await recorder.requestPermission() }
    public func requestSpeechPermission() async -> Bool { true }
    public func captureStates() -> AsyncStream<AudioCaptureState> { captureStateSubject.stream() }
    public func audioLevels() -> AsyncStream<Float> { recorder.audioLevels() }
    func captureDeviceStates() -> AsyncStream<AudioCaptureState> { recorder.captureStates() }
    func interruptCapture() async {
        await stop()
        captureStateSubject.send(.interrupted)
        sessionRelay.send(.state(.interrupted))
    }


    public var isTranscribing: Bool {
        _isTranscribing.withLock { $0 }
    }

    public func start(language: Locale) async throws {
        logger.info("start()", fields: [.label("language", .source("locale"))])

        if _isTranscribing.withLock({ $0 }) {
            logger.warning("Already recording, stopping first")
            await stop()
        }

        recordingLocale = language

        let silenceDuration = config.autoStopSilenceDuration
        let silenceThreshold = config.silenceThreshold

        // 录音中监听音量，实现静音自动停止
        try await recorder.start(bufferHandler: nil)

        // 通过 audioLevelPublisher 监听音量做静音检测
        // 注意：此 Task 在 start() 返回后在后台运行
        silenceTask?.cancel()
        if silenceDuration > 0 {
            silenceTask = Task { [weak self] in
                guard let self else { return }
                var silentSince: Date? = nil

                for await level in self.recorder.audioLevels() {
                    guard !Task.isCancelled else { return }
                    if level > silenceThreshold {
                        silentSince = nil
                    } else {
                        let now = Date()
                        let start = silentSince ?? { silentSince = now; return now }()
                        if now.timeIntervalSince(start) >= silenceDuration {
                            self.logger.info("Auto-stop: silence", fields: [.double("silence_seconds", silenceDuration)])
                            await self.stop()
                            return
                        }
                    }
                }
            }
        }

        captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
        _isTranscribing.withLock { $0 = true }
        recordingStartTime = Date()
        logger.info("Recording started")
    }

    public func stop() async {
        logger.info("stop() called")
        defer { sessionRelay.finish() }

        silenceTask?.cancel()
        silenceTask = nil

        let fileURL = recorder.stop()
        captureStateSubject.send(.idle); sessionRelay.send(.state(.idle))
        _isTranscribing.withLock { $0 = false }

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil

        guard let fileURL else {
            logger.warning("No audio file to transcribe")
            return
        }

        guard duration >= 0.5 else {
            logger.warning("Recording too short, skipping Whisper", fields: [.double("duration_seconds", duration)])
            try? await Task.detached { [temporaryAudioStore] in try temporaryAudioStore.remove(fileURL) }.value
            return
        }

        do {
            let text = try await whisperEngine.transcribe(fileURL: fileURL, language: recordingLocale)
            let result = TranscriptionResult(
                text: text, type: .final,
                confidence: nil, timestamp: Date(), locale: recordingLocale
            )
            sessionRelay.send(.partial(result))
            sessionRelay.send(.final(result))
        } catch {
            sessionRelay.finish(throwing: error)
            logger.error("Whisper error")
        }

        try? await Task.detached { [temporaryAudioStore] in try temporaryAudioStore.remove(fileURL) }.value
    }

    public func pause() {
        recorder.pause()
        captureStateSubject.send(.paused); sessionRelay.send(.state(.paused))
    }

    public func resume() {
        recorder.resume()
        captureStateSubject.send(.recording); sessionRelay.send(.state(.recording))
    }
}
