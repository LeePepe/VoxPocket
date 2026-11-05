import AVFoundation
import Foundation
import VoxCore
import Synchronization

/// 麦克风录音器
///
/// 专注于音频采集：请求权限、启动 AVAudioEngine、写入临时 WAV 文件，
/// 并通过 `bufferHandler` 同步回调将每个 PCM buffer 分发给外部消费者（如语音识别引擎）。
/// 不包含任何转录逻辑。
// Sendable: AVAudioEngine callbacks own audio writes; lifecycle configuration runs on MainActor.
public final class MicrophoneRecorder: NSObject, AudioBufferSource, @unchecked Sendable {

    // MARK: - Private state

    private let audioEngine = AVAudioEngine()
    private struct State: @unchecked Sendable {
        var audioFile: AVAudioFile?
        var tempFileURL: URL?
        var interruptedFileURL: URL?
        var notificationTokens: [NSObjectProtocol] = []
    }
    private let lifecycleState = Mutex(State())

    private let audioLevelSubject = AsyncValueRelay<Float>(0)
    private let captureStateSubject = AsyncValueRelay<AudioCaptureState>(.idle)
    private let logger: any VoxLogger
    private let authorizationProvider: any MicrophoneAuthorizationProviding
    private let temporaryAudioStore: TemporaryAudioStore

    // MARK: - Public publishers

    public func audioLevels() -> AsyncStream<Float> { audioLevelSubject.stream() }
    public func captureStates() -> AsyncStream<AudioCaptureState> { captureStateSubject.stream() }
    public var state: AudioCaptureState { captureStateSubject.value }

    // MARK: - Init

    public init(
        logger: any VoxLogger = NoopVoxLogger(),
        storageLocations: VoxStorageLocations
    ) {
        self.logger = logger
        self.authorizationProvider = SystemMicrophoneAuthorizationProvider()
        self.temporaryAudioStore = TemporaryAudioStore(storageLocations: storageLocations)
    }

    init(
        logger: any VoxLogger = NoopVoxLogger(),
        authorizationProvider: any MicrophoneAuthorizationProviding,
        storageLocations: VoxStorageLocations
    ) {
        self.logger = logger
        self.authorizationProvider = authorizationProvider
        self.temporaryAudioStore = TemporaryAudioStore(storageLocations: storageLocations)
    }

    deinit {
        lifecycleState.withLock { state in
            state.notificationTokens.forEach(NotificationCenter.default.removeObserver)
        }
    }

    // MARK: - Permissions

    /// 请求麦克风权限，返回是否已授权
    public func requestPermission() async -> Bool {
        await authorizationProvider.requestMicrophoneAccess()
    }

    public var hasPermission: Bool {
        authorizationProvider.hasMicrophoneAccess
    }

    // MARK: - Recording

    /// 开始录音
    ///
    /// - Parameter bufferHandler: 每个 PCM buffer 的同步回调（在音频线程调用）。
    ///   可用于将 buffer 实时喂给语音识别引擎。
    func start(bufferHandler: ((AVAudioPCMBuffer) -> Void)? = nil) async throws {
        try await startIfAllowed(shouldStart: { true }, bufferHandler: bufferHandler)
    }

    func startIfAllowed(
        shouldStart: @escaping @Sendable () -> Bool,
        bufferHandler: ((AVAudioPCMBuffer) -> Void)? = nil
    ) async throws {
        guard shouldStart() else { throw CancellationError() }
        guard await requestPermission() else { throw VoxKitError.microphoneAccessDenied }
        installAudioSessionObservers()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        try Task.checkCancellation()
        guard shouldStart() else { throw CancellationError() }

        // 用户音频只在应用数据目录暂存；目录创建不占用主线程。
        let store = temporaryAudioStore
        let tempURL = try await Task.detached { try store.makeRecordingFileURL() }.value
        lifecycleState.withLock { $0.tempFileURL = tempURL }

        // Tap callback must be defined OUTSIDE MainActor.run so it does not inherit
        // MainActor isolation. AVAudioEngine calls it on the realtime audio thread;
        // if the closure were @MainActor, Swift's runtime isolation check would crash.
        // Sendable: the tap invokes this handler only on the AVAudioEngine callback thread.
        nonisolated(unsafe) let handler = bufferHandler
        // Sendable: AVAudioEngine retains this callback; configuration stays on MainActor.
        nonisolated(unsafe) let tapBlock: (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
            guard let self else { return }
            self.lifecycleState.withLock { state in
                try? state.audioFile?.write(from: buffer)
            }
            let level = self.rmsLevel(buffer: buffer)
            self.audioLevelSubject.send(level)
            handler?(buffer)
        }

        // AVAudioEngine node configuration must run on the main thread.
        try await MainActor.run {
            try lifecycleState.withLock {
                guard shouldStart() else { throw CancellationError() }
                let inputNode = audioEngine.inputNode
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                let format = inputNode.inputFormat(forBus: 0)
                $0.audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
                logger.debug("Recording file prepared", fields: [.double("sample_rate", format.sampleRate), .int("channel_count", Int(format.channelCount))])

                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapBlock)

                audioEngine.prepare()
                guard shouldStart() else { throw CancellationError() }
                try audioEngine.start()
                captureStateSubject.send(.recording)
            }
        }
        logger.info("Recording started")
    }

    /// 停止录音
    ///
    /// - Returns: 临时 WAV 文件 URL，调用方负责在使用完毕后删除。无录音时返回 nil。
    @discardableResult
    public func stop() -> URL? {
        let url = lifecycleState.withLock { state -> URL? in
            guard let url = state.tempFileURL else {
                defer { state.interruptedFileURL = nil }
                return state.interruptedFileURL
            }
            state.tempFileURL = nil
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            state.audioFile = nil
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            captureStateSubject.send(.idle)
            audioLevelSubject.send(0)
            return url
        }
        logger.info("Recording stopped", fields: [.bool("has_file", url != nil)])
        return url
    }

    public func pause() {
        lifecycleState.withLock { _ in
            audioEngine.pause()
            captureStateSubject.send(.paused)
        }
        logger.debug("Paused")
    }

    public func resume() {
        lifecycleState.withLock { _ in
            try? audioEngine.start()
            captureStateSubject.send(.recording)
        }
        logger.debug("Resumed")
    }

    // MARK: - Internal

    private func installAudioSessionObservers() {
        #if os(iOS)
        lifecycleState.withLock { state in
            guard state.notificationTokens.isEmpty else { return }
            let center = NotificationCenter.default
            state.notificationTokens = [
                center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
                    guard let self else { return }
                    if let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                       AVAudioSession.InterruptionType(rawValue: type) == .began {
                        self.stopForInterruption()
                    }
                },
                center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] note in
                    guard Self.isDeviceRemoval(note) else { return }
                    self?.stopForInterruption()
                }
            ]
        }
        #endif
    }

    #if os(iOS)
    private func stopForInterruption() {
        lifecycleState.withLock { state in
            guard let file = state.tempFileURL else { return }
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            state.audioFile = nil
            state.tempFileURL = nil
            state.interruptedFileURL = file
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioLevelSubject.send(0)
            captureStateSubject.send(.interrupted)
        }
    }

    static func isDeviceRemoval(_ notification: Notification) -> Bool {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return false }
        return AVAudioSession.RouteChangeReason(rawValue: reason) == .oldDeviceUnavailable
    }
    #endif

    private func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        let ptr = channelData.pointee
        var sum: Float = 0
        for i in 0..<frameLength { let s = ptr[i]; sum += s * s }
        let rms = (sum / Float(frameLength)).squareRoot()
        let db = 20 * log10f(max(rms, 0.000001))
        return min(1, max(0, (db + 80) / 80))
    }
}
