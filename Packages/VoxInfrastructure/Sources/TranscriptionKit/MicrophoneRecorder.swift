import AVFoundation
import Combine
import Foundation
import Observability

/// 麦克风录音器
///
/// 专注于音频采集：请求权限、启动 AVAudioEngine、写入临时 WAV 文件，
/// 并通过 `bufferHandler` 同步回调将每个 PCM buffer 分发给外部消费者（如语音识别引擎）。
/// 不包含任何转录逻辑。
public final class MicrophoneRecorder: NSObject, @unchecked Sendable {

    // MARK: - Private state

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?

    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)
    private let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)
    private let logger: Logger

    // MARK: - Public publishers

    public var audioLevelPublisher: AnyPublisher<Float, Never> { audioLevelSubject.eraseToAnyPublisher() }
    public var statePublisher: AnyPublisher<AudioCaptureState, Never> { captureStateSubject.eraseToAnyPublisher() }
    public var state: AudioCaptureState { captureStateSubject.value }

    // MARK: - Init

    public init(logger: Logger = PrintLogger(subsystem: "MicrophoneRecorder")) {
        self.logger = logger
    }

    // MARK: - Permissions

    /// 请求麦克风权限，返回是否已授权
    public func requestPermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { c in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    public var hasPermission: Bool {
        #if os(iOS)
        AVAudioSession.sharedInstance().recordPermission == .granted
        #else
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif
    }

    // MARK: - Recording

    /// 开始录音
    ///
    /// - Parameter bufferHandler: 每个 PCM buffer 的同步回调（在音频线程调用）。
    ///   可用于将 buffer 实时喂给语音识别引擎。
    public func start(bufferHandler: ((AVAudioPCMBuffer) -> Void)? = nil) async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #else
        let authorized = await AVCaptureDevice.requestAccess(for: .audio)
        guard authorized else {
            throw NSError(
                domain: "MicrophoneRecorder", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "麦克风权限未授权"]
            )
        }
        #endif

        let inputNode = audioEngine.inputNode
        if audioEngine.isRunning {
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
        } else {
            inputNode.removeTap(onBus: 0)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mic_\(UUID().uuidString).wav")
        tempFileURL = tempURL

        let format = inputNode.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        logger.debug("Recording to \(tempURL.lastPathComponent), \(format.sampleRate)Hz \(format.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            let level = self.rmsLevel(buffer: buffer)
            self.audioLevelSubject.send(level)
            bufferHandler?(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        captureStateSubject.send(.recording)
        logger.info("Recording started")
    }

    /// 停止录音
    ///
    /// - Returns: 临时 WAV 文件 URL，调用方负责在使用完毕后删除。无录音时返回 nil。
    @discardableResult
    public func stop() -> URL? {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        captureStateSubject.send(.idle)
        audioLevelSubject.send(0)
        let url = tempFileURL
        tempFileURL = nil
        logger.info("Recording stopped → \(url?.lastPathComponent ?? "nil")")
        return url
    }

    public func pause() {
        audioEngine.pause()
        captureStateSubject.send(.paused)
        logger.debug("Paused")
    }

    public func resume() {
        try? audioEngine.start()
        captureStateSubject.send(.recording)
        logger.debug("Resumed")
    }

    // MARK: - Internal

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
