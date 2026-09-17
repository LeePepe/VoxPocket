#if os(macOS)
import AudioToolbox
import Foundation

private final class EncodedBenchmarkAudio {
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
}

struct BenchmarkAudio: Sendable {
    let samples: [Float]
    var duration: Double { Double(samples.count) / 16000 }

    /// Core Audio 只读已校验的内存快照，不重开任何私密文件路径。
    static func decode(_ bytes: Data) throws -> BenchmarkAudio {
        let retained = Unmanaged.passRetained(EncodedBenchmarkAudio(bytes))
        defer { retained.release() }
        var audioFile: AudioFileID?
        let opened = AudioFileOpenWithCallbacks(retained.toOpaque(), { client, offset, requested, output, actual in
            let data = Unmanaged<EncodedBenchmarkAudio>.fromOpaque(client).takeUnretainedValue().bytes
            guard offset >= 0, offset <= Int64(data.count) else { actual.pointee = 0; return noErr }
            let count = min(Int(requested), data.count - Int(offset))
            if count > 0 {
                data.withUnsafeBytes { raw in
                    output.copyMemory(from: raw.baseAddress!.advanced(by: Int(offset)), byteCount: count)
                }
            }
            actual.pointee = UInt32(count)
            return noErr
        }, nil, { client in
            Int64(Unmanaged<EncodedBenchmarkAudio>.fromOpaque(client).takeUnretainedValue().bytes.count)
        }, nil, 0, &audioFile)
        guard opened == noErr, let audioFile else { throw BenchmarkFailure.invalidAudio }
        defer { AudioFileClose(audioFile) }
        return try decodeFile(audioFile)
    }

    private static func decodeFile(_ audioFile: AudioFileID) throws -> BenchmarkAudio {
        var extended: ExtAudioFileRef?
        guard ExtAudioFileWrapAudioFileID(audioFile, false, &extended) == noErr, let extended else {
            throw BenchmarkFailure.invalidAudio
        }
        defer { ExtAudioFileDispose(extended) }
        var format = AudioStreamBasicDescription(mSampleRate: 16000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4,
            mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        guard ExtAudioFileSetProperty(extended, kExtAudioFileProperty_ClientDataFormat,
                                      UInt32(MemoryLayout.size(ofValue: format)), &format) == noErr else {
            throw BenchmarkFailure.invalidAudio
        }
        var samples = Array(repeating: Float(0), count: 960001)
        var frames: UInt32 = 960001
        let status = samples.withUnsafeMutableBytes { raw in
            var buffers = AudioBufferList(mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            return ExtAudioFileRead(extended, &frames, &buffers)
        }
        guard status == noErr, frames > 0, frames <= 960000 else { throw BenchmarkFailure.invalidAudio }
        samples = Array(samples.prefix(Int(frames)))
        guard samples.allSatisfy({ $0.isFinite && abs($0) <= 16 }) else { throw BenchmarkFailure.invalidAudio }
        return BenchmarkAudio(samples: samples)
    }

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
