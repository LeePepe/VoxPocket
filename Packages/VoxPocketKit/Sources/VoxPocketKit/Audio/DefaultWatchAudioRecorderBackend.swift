import Foundation
import Synchronization
#if canImport(AVFoundation)
@preconcurrency import AVFoundation

// Sendable: 单个 capture service actor 独占录音器调用；系统 delegate 只通过 Mutex 更新状态，不触碰 UI。
public final class DefaultWatchAudioRecorderBackend: NSObject, WatchAudioRecorderBackend, AVAudioRecorderDelegate, @unchecked Sendable {
    private struct State { var recorder: AVAudioRecorder?; var failed = false; var stopping = false }
    private let state = Mutex(State())

    public func requestPermission() async -> Bool {
        await WatchAudioPermissionRequest().value { completion in
            #if os(iOS) || os(watchOS) || os(visionOS)
            AVAudioApplication.requestRecordPermission { completion($0) }
            #else
            AVCaptureDevice.requestAccess(for: .audio) { completion($0) }
            #endif
        }
    }
    public func start(url: URL, configuration: WatchAudioRecordingConfiguration) throws {
        do {
            #if os(iOS) || os(watchOS) || os(visionOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: configuration.sampleRate,
                                          AVNumberOfChannelsKey: configuration.channels, AVEncoderBitRateKey: configuration.bitRate]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true; recorder.delegate = self
            state.withLock { $0.recorder = recorder; $0.failed = false; $0.stopping = false }
            guard recorder.record() else { throw WatchCaptureError.captureFailed }
        } catch { cancel(); throw WatchCaptureError.captureFailed }
    }
    public func stop() throws {
        let recorder = state.withLock { value -> AVAudioRecorder? in value.stopping = true; return value.recorder }
        recorder?.stop()
        let failed = state.withLock { value in let failed = value.failed; value.recorder = nil; return failed }
        deactivate()
        guard recorder != nil, !failed else { throw WatchCaptureError.captureFailed }
    }
    public func cancel() {
        let recorder = state.withLock { value -> AVAudioRecorder? in value.stopping = true; let recorder = value.recorder; value.recorder = nil; return recorder }
        recorder?.stop(); recorder?.deleteRecording(); deactivate()
    }
    public func currentPower() throws -> Float {
        try state.withLock { value in
            guard !value.failed, let recorder = value.recorder, recorder.isRecording else { throw WatchCaptureError.captureFailed }
            recorder.updateMeters()
            let db = recorder.averagePower(forChannel: 0)
            return db.isFinite ? min(max(pow(10, db / 20), 0), 1) : 0
        }
    }
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        state.withLock { if !flag || !$0.stopping { $0.failed = true } }
    }
    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { state.withLock { $0.failed = true } }
    private func deactivate() {
        #if os(iOS) || os(watchOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
#else
public struct DefaultWatchAudioRecorderBackend: WatchAudioRecorderBackend {
    public init() {}
    public func requestPermission() async -> Bool { false }
    public func start(url: URL, configuration: WatchAudioRecordingConfiguration) throws { throw WatchCaptureError.unavailable }
    public func stop() throws { throw WatchCaptureError.unavailable }
    public func cancel() {}
    public func currentPower() throws -> Float { 0 }
}
#endif
