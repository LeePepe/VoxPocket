import AVFoundation
import Foundation
import Synchronization

/// 音频 tap 只复制有界快照；AVAudioConverter 和网络均在后台串行执行。
struct RealtimeAudioSnapshot: Sendable {
    let sampleRate: Double
    let channels: [Data]
    let frames: AVAudioFrameCount

    init(_ buffer: AVAudioPCMBuffer) throws {
        guard buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved,
              buffer.format.sampleRate >= 8_000, buffer.format.sampleRate <= 192_000,
              buffer.format.channelCount > 0, buffer.format.channelCount <= 8,
              buffer.frameLength > 0, buffer.frameLength <= 8192,
              let data = buffer.floatChannelData else { throw RealtimeTranscriptionError.unsupportedAudio }
        sampleRate = buffer.format.sampleRate
        frames = buffer.frameLength
        channels = (0..<Int(buffer.format.channelCount)).map {
            Data(bytes: data[$0], count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }
    }

    func buffer() throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: UInt32(channels.count)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let output = buffer.floatChannelData else { throw RealtimeTranscriptionError.unsupportedAudio }
        buffer.frameLength = frames
        for (index, data) in channels.enumerated() {
            data.copyBytes(to: UnsafeMutableRawBufferPointer(start: output[index], count: data.count))
        }
        return buffer
    }
}

/// 单一后台任务独占 converter，包含跨 buffer 的重采样状态和末尾排空。
final class RealtimePCMConverter {
    private var converter: AVAudioConverter?
    private let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000,
                                       channels: 1, interleaved: true)!

    func convert(_ snapshot: RealtimeAudioSnapshot) throws -> Data {
        let input = try snapshot.buffer()
        if converter == nil { converter = AVAudioConverter(from: input.format, to: output) }
        guard let converter, converter.inputFormat == input.format else {
            throw RealtimeTranscriptionError.unsupportedAudio
        }
        return try drain(input, converter: converter, end: false)
    }

    func finish() throws -> Data {
        guard let converter else { return Data() }
        return try drain(nil, converter: converter, end: true)
    }

    private func drain(_ input: AVAudioPCMBuffer?, converter: AVAudioConverter, end: Bool) throws -> Data {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 16_384) else {
            throw RealtimeTranscriptionError.unsupportedAudio
        }
        var supplied = false
        var result = Data()
        // 每次输入最多 8192 帧；最多 8k→24k 三倍。额外一轮用于 converter 尾部。
        for _ in 0..<4 {
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { _, status in
                if !supplied, let input { supplied = true; status.pointee = .haveData; return input }
                status.pointee = end ? .endOfStream : .noDataNow
                return nil
            }
            guard status != .error, error == nil else { throw RealtimeTranscriptionError.unsupportedAudio }
            if let samples = buffer.int16ChannelData, buffer.frameLength > 0 {
                result.append(Data(bytes: samples[0], count: Int(buffer.frameLength) * 2))
            }
            if status == .inputRanDry || status == .endOfStream { return result }
        }
        throw RealtimeTranscriptionError.unsupportedAudio
    }
}

final class RealtimeAudioPipeline: Sendable {
    private let session: DefaultRealtimeTranscriptionSession
    private let stream: AsyncThrowingStream<RealtimeAudioSnapshot, Error>
    private let continuation: AsyncThrowingStream<RealtimeAudioSnapshot, Error>.Continuation
    private let worker = Mutex<Task<String, Error>?>(nil)

    init(session: DefaultRealtimeTranscriptionSession, capacity: Int = 128) {
        self.session = session
        let pair = AsyncThrowingStream<RealtimeAudioSnapshot, Error>.makeStream(bufferingPolicy: .bufferingOldest(capacity))
        stream = pair.stream
        continuation = pair.continuation
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        do {
            if case .dropped = continuation.yield(try RealtimeAudioSnapshot(buffer)) {
                continuation.finish(throwing: RealtimeTranscriptionError.audioOverflow)
            }
        } catch { continuation.finish(throwing: RealtimeTranscriptionError.unsupportedAudio) }
    }

    /// 麦克风授权及启动完成之后才连远端，避免权限对话框期间开启计费会话。
    func start(language: String) {
        worker.withLock { task in
            guard task == nil else { return }
            task = Task.detached { [stream, session] in
                do {
                    try await session.open(language: language)
                    let converter = RealtimePCMConverter()
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        let data = try converter.convert(snapshot)
                        if !data.isEmpty { try await session.append(data) }
                    }
                    let tail = try converter.finish()
                    if !tail.isEmpty { try await session.append(tail) }
                    return try await session.finish()
                } catch {
                    await session.cancel()
                    throw (error as? RealtimeTranscriptionError) ?? .connectionFailed
                }
            }
        }
    }

    func finish(timeout: Duration = .seconds(8)) async throws -> String {
        continuation.finish()
        guard let task = worker.withLock({ $0 }) else { throw RealtimeTranscriptionError.cancelled }
        let deadline = Task { [self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            cancel()
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { self.cancel() }
    }

    func cancel() {
        continuation.finish(throwing: RealtimeTranscriptionError.cancelled)
        worker.withLock { $0 }?.cancel()
        Task { [session] in await session.cancel() }
    }

    deinit {
        continuation.finish()
        worker.withLock { $0 }?.cancel()
        Task { [session] in await session.cancel() }
    }
}

enum RealtimeASRFinalizer {
    /// 健康流式不调用整文件接口；失败仅回退一次，refine 不属于这里。
    static func resolve(realtime: () async throws -> String, fallback: () async throws -> String) async throws -> String {
        do { return try await realtime() }
        catch {
            try Task.checkCancellation()
            return try await fallback()
        }
    }
}
