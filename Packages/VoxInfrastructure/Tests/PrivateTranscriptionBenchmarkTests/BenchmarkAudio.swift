#if os(macOS)
import AVFoundation
import Foundation

struct BenchmarkAudio: Sendable {
    let samples: [Float]
    var duration: Double { Double(samples.count) / 16000 }

    /// 一次解码、单声道 16kHz；识别时两种适配器消费同一 PCM。
    static func decode(_ url: URL) throws -> BenchmarkAudio {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length < AVAudioFramePosition(file.processingFormat.sampleRate * 60),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let target = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960001) else {
            throw BenchmarkFailure.invalidAudio
        }
        try file.read(into: source)
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: target, error: &conversionError) { _, outputStatus in
            if supplied { outputStatus.pointee = .endOfStream; return nil }
            supplied = true; outputStatus.pointee = .haveData; return source
        }
        guard status != .error, conversionError == nil, target.frameLength > 0,
              target.frameLength <= 960000, let data = target.floatChannelData else {
            throw BenchmarkFailure.invalidAudio
        }
        return BenchmarkAudio(samples: Array(UnsafeBufferPointer(start: data[0], count: Int(target.frameLength))))
    }

    /// 固定 PCM16 WAV；先量化再返回供 Apple 使用的样本，消除输入量化差异。
    func canonicalized() -> BenchmarkAudio {
        BenchmarkAudio(samples: samples.map { Float(Int16(max(-32768, min(32767, Int($0 * 32767))))) / 32768 })
    }

    func wav() -> Data {
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(UInt32(36 + samples.count * 2)); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        ascii("data"); u32(UInt32(samples.count * 2))
        for sample in samples { u16(UInt16(bitPattern: Int16(max(-32768, min(32767, Int(sample * 32768)))))) }
        return data
    }
}
#endif
