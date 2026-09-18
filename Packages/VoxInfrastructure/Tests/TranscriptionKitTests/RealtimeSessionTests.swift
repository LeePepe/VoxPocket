import Foundation
import Synchronization
import XCTest
@testable import TranscriptionKit

actor FakeRealtimeTransport: RealtimeTranscriptionTransport {
    private var pending: [Data] = []
    private var waiting: [CheckedContinuation<Data, Error>] = []
    private var closed = false
    private let acknowledge: Bool
    private let completeOnCommit: Bool
    private(set) var sent: [String] = []

    init(acknowledge: Bool = true, completeOnCommit: Bool = true) {
        self.acknowledge = acknowledge
        self.completeOnCommit = completeOnCommit
    }
    func connect(request: URLRequest) async throws {}
    func send(_ data: Data) async throws {
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let type = object["type"] as! String
        sent.append(type)
        if type == "session.update", acknowledge {
            enqueue(#"{"type":"session.updated"}"#)
        } else if type == "input_audio_buffer.append" {
            enqueue(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"one","delta":"你好"}"#)
        } else if type == "input_audio_buffer.commit" {
            enqueue(#"{"type":"input_audio_buffer.committed","item_id":"one"}"#)
            if completeOnCommit {
                enqueue(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"one","transcript":"你好世界。"}"#)
            }
        }
    }
    func receive() async throws -> Data {
        if !pending.isEmpty { return pending.removeFirst() }
        if closed { throw RealtimeTranscriptionError.connectionFailed }
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }
    func close() async {
        closed = true
        let continuations = waiting; waiting.removeAll()
        continuations.forEach { $0.resume(throwing: RealtimeTranscriptionError.connectionFailed) }
    }
    func enqueue(_ json: String) {
        let data = Data(json.utf8)
        if !waiting.isEmpty { waiting.removeFirst().resume(returning: data) }
        else { pending.append(data) }
    }
}

final class RealtimeSessionTests: XCTestCase {
    private func config() throws -> AzureRealtimeTranscriptionConfig {
        try .init(endpoint: URL(string: "https://example.invalid")!, apiKey: "synthetic-key", deployment: "live")
    }

    func testPartialArrivesBeforeFinishAndFinishCommitsOnce() async throws {
        let socket = FakeRealtimeTransport()
        let partial = expectation(description: "partial before stop")
        let session = DefaultRealtimeTranscriptionSession(config: try config(), transport: socket) { text in
            if text == "你好" { partial.fulfill() }
        }
        try await session.open(language: "zh")
        try await session.append(Data(repeating: 0, count: 4800))
        await fulfillment(of: [partial], timeout: 1)
        let beforeStop = await socket.sent
        XCTAssertFalse(beforeStop.contains("input_audio_buffer.commit"))
        let first = try await session.finish()
        let second = try await session.finish()
        XCTAssertEqual(first, "你好世界。")
        XCTAssertEqual(second, first)
        let messages = await socket.sent
        XCTAssertEqual(messages.filter { $0 == "input_audio_buffer.commit" }.count, 1)
    }

    func testSessionTimeoutClosesWithoutLeakingProviderMessages() async throws {
        let socket = FakeRealtimeTransport(acknowledge: false)
        let session = DefaultRealtimeTranscriptionSession(config: try config(), transport: socket,
                                                         timeout: .milliseconds(25), onPartial: { _ in })
        do { try await session.open(language: "zh"); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? RealtimeTranscriptionError, .timeout) }
    }

    func testProviderErrorBodyIsNeverPropagated() async throws {
        let socket = FakeRealtimeTransport(acknowledge: false)
        await socket.enqueue(#"{"type":"error","error":{"message":"PRIVATE_SENTINEL"}}"#)
        let session = DefaultRealtimeTranscriptionSession(config: try config(), transport: socket, onPartial: { _ in })
        do { try await session.open(language: "zh"); XCTFail("Expected error") }
        catch {
            XCTAssertEqual(error as? RealtimeTranscriptionError, .protocolRejected)
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_SENTINEL"))
        }
    }

    func testCancellationReleasesFinalWaiter() async throws {
        let socket = FakeRealtimeTransport(completeOnCommit: false)
        let session = DefaultRealtimeTranscriptionSession(config: try config(), transport: socket, onPartial: { _ in })
        try await session.open(language: "zh")
        try await session.append(Data(repeating: 0, count: 4800))
        let finishing = Task { try await session.finish() }
        for _ in 0..<100 {
            if await socket.sent.contains("input_audio_buffer.commit") { break }
            await Task.yield()
        }
        await session.cancel()
        do { _ = try await finishing.value; XCTFail("Expected cancellation") }
        catch { XCTAssertEqual(error as? RealtimeTranscriptionError, .cancelled) }
    }

    func testCompletionOrderAndDuplicatesDoNotCorruptTranscript() throws {
        var buffer = RealtimeTranscriptBuffer()
        try buffer.commit(itemID: "first")
        try buffer.commit(itemID: "second")
        try buffer.complete(itemID: "second", text: "第二句。")
        XCTAssertNil(buffer.finalText)
        try buffer.append(itemID: "first", delta: "第一")
        try buffer.complete(itemID: "first", text: "第一句。")
        try buffer.complete(itemID: "first", text: "第一句。")
        try buffer.append(itemID: "first", delta: "晚到的旧片段")
        XCTAssertEqual(buffer.finalText, "第一句。第二句。")
    }

    func testTranscriptBoundIsGlobalAndContradictoryFinalFails() throws {
        var buffer = RealtimeTranscriptBuffer()
        try buffer.append(itemID: "one", delta: String(repeating: "a", count: 600_000))
        XCTAssertThrowsError(try buffer.append(itemID: "two", delta: String(repeating: "b", count: 600_000)))
        try buffer.complete(itemID: "one", text: "final")
        XCTAssertThrowsError(try buffer.complete(itemID: "one", text: "different"))
    }

    func testLateEventsFromCancelledSessionCannotAffectNewSession() async throws {
        let oldSocket = FakeRealtimeTransport()
        let oldValues = Mutex<[String]>([])
        let old = DefaultRealtimeTranscriptionSession(config: try config(), transport: oldSocket) { text in
            oldValues.withLock { $0.append(text) }
        }
        try await old.open(language: "zh")
        await old.cancel()
        await oldSocket.enqueue(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"old","delta":"旧文字"}"#)
        let newSocket = FakeRealtimeTransport()
        let new = DefaultRealtimeTranscriptionSession(config: try config(), transport: newSocket, onPartial: { _ in })
        try await new.open(language: "zh")
        try await new.append(Data(repeating: 0, count: 4800))
        let result = try await new.finish()
        XCTAssertEqual(result, "你好世界。")
        XCTAssertTrue(oldValues.withLock { $0.isEmpty })
    }

    func testFinalResponseTimeoutIsBounded() async throws {
        let socket = FakeRealtimeTransport(completeOnCommit: false)
        let session = DefaultRealtimeTranscriptionSession(config: try config(), transport: socket,
                                                         timeout: .milliseconds(30), onPartial: { _ in })
        try await session.open(language: "zh")
        try await session.append(Data(repeating: 0, count: 4800))
        do { _ = try await session.finish(); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? RealtimeTranscriptionError, .timeout) }
    }
}
