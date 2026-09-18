import AVFoundation
import Foundation
import Synchronization
import XCTest
@testable import TranscriptionKit

final class RealtimeAudioTests: XCTestCase {
    private func audio(rate: Double = 48_000, channels: UInt32 = 2, frames: UInt32 = 1024) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) { buffer.floatChannelData![channel][frame] = sin(Float(frame) * 0.1) * 0.2 }
        }
        return buffer
    }

    func testSnapshotOwnsCopyAndConverterProduces24kMonoPCM16() throws {
        let source = audio(frames: 4800 / 2)
        let snapshot = try RealtimeAudioSnapshot(source)
        let before = snapshot.channels
        source.floatChannelData![0][0] = 1
        XCTAssertEqual(snapshot.channels, before)
        let restored = try snapshot.buffer()
        XCTAssertNotEqual(restored.floatChannelData![0][0], 1)
        let converter = RealtimePCMConverter()
        var output = try converter.convert(snapshot)
        output.append(try converter.finish())
        XCTAssertEqual(output.count, 2400, accuracy: 8)
        XCTAssertTrue(output.count.isMultiple(of: 2))
    }

    func testUnsupportedAndOversizedSnapshotsFail() {
        XCTAssertThrowsError(try RealtimeAudioSnapshot(audio(frames: 16_384)))
        XCTAssertThrowsError(try RealtimeAudioSnapshot(audio(rate: 4_000)))
    }

    func testPipelineDrainsAudioAndCommitsOnce() async throws {
        let socket = FakeRealtimeTransport()
        let session = DefaultRealtimeTranscriptionSession(config: try config(), transport: socket, onPartial: { _ in })
        let pipeline = RealtimeAudioPipeline(session: session)
        for _ in 0..<10 { pipeline.append(audio()) }
        pipeline.start(language: "zh")
        let result = try await pipeline.finish()
        XCTAssertEqual(result, "你好世界。")
        let events = await socket.sent
        XCTAssertEqual(events.filter { $0 == "input_audio_buffer.commit" }.count, 1)
        XCTAssertEqual(events.last, "input_audio_buffer.commit")
    }

    func testBoundedQueueOverflowFailsRatherThanDroppingAudio() async throws {
        let socket = FakeRealtimeTransport()
        let session = DefaultRealtimeTranscriptionSession(config: try config(), transport: socket, onPartial: { _ in })
        let pipeline = RealtimeAudioPipeline(session: session, capacity: 1)
        pipeline.append(audio()); pipeline.append(audio())
        pipeline.start(language: "zh")
        do { _ = try await pipeline.finish(); XCTFail("Expected overflow") }
        catch { XCTAssertEqual(error as? RealtimeTranscriptionError, .audioOverflow) }
        let events = await socket.sent
        XCTAssertFalse(events.contains("input_audio_buffer.commit"))
    }

    func testNoFinalResponseCannotHangPipeline() async throws {
        let socket = FakeRealtimeTransport(completeOnCommit: false)
        let session = DefaultRealtimeTranscriptionSession(config: try config(), transport: socket, onPartial: { _ in })
        let pipeline = RealtimeAudioPipeline(session: session)
        for _ in 0..<10 { pipeline.append(audio()) }
        pipeline.start(language: "zh")
        do { _ = try await pipeline.finish(timeout: .milliseconds(50)); XCTFail("Expected cancellation") }
        catch { XCTAssertEqual(error as? RealtimeTranscriptionError, .cancelled) }
    }

    func testHealthyStreamingSkipsBatchAndFailureFallsBackOnce() async throws {
        var fallbackCount = 0
        let streamed = try await RealtimeASRFinalizer.resolve(realtime: { "streamed" }, fallback: {
            fallbackCount += 1; return "batch"
        })
        XCTAssertEqual(streamed, "streamed")
        XCTAssertEqual(fallbackCount, 0)
        let fallback = try await RealtimeASRFinalizer.resolve(realtime: { throw RealtimeTranscriptionError.timeout }, fallback: {
            fallbackCount += 1; return "batch"
        })
        XCTAssertEqual(fallback, "batch")
        XCTAssertEqual(fallbackCount, 1)
    }

    private func config() throws -> AzureRealtimeTranscriptionConfig {
        try .init(endpoint: URL(string: "https://example.invalid")!, apiKey: "synthetic", deployment: "live")
    }
}
