import XCTest
@testable import VoxPocketKit

final class WatchCaptureTests: XCTestCase {
    func testMetadataRejectsPathTraversalAndWrongSource() throws {
        let id = UUID()
        XCTAssertThrowsError(try WatchCaptureMetadata(captureID: id, duration: 1, basename: "../\(id.uuidString).m4a"))
        XCTAssertThrowsError(try WatchCaptureMetadata(captureID: id, duration: 1, source: .iPhone, basename: "\(id.uuidString).m4a"))
    }

    func testBridgeQueuesOfflineCaptureAndReplaysOnActivation() async throws {
        let id = UUID()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString).m4a")
        try Data(repeating: 1, count: 8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = FakeTransport()
        let storage = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let bridge = VoxWatchSyncBridge(transport: transport, storageDirectory: storage)
        let capture = WatchAudioCapture(captureID: id, fileURL: url, duration: 1)
        _ = try await bridge.send(capture: capture)
        let queuedTransfers = await transport.transfers
        XCTAssertEqual(queuedTransfers.count, 0)
        await transport.setReachable(true)
        try await bridge.activate()
        let replayedTransfers = await transport.transfers
        XCTAssertEqual(replayedTransfers.count, 1)
    }

    func testCoordinatorPersistsCompletionAndDeduplicatesDelivery() async throws {
        let id = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("\(id.uuidString).m4a")
        try Data(repeating: 1, count: 32).write(to: url)
        let metadata = try WatchCaptureMetadata(captureID: id, duration: 2, basename: url.lastPathComponent)
        let persistence = InMemoryWatchIngestPersistence()
        let receiptStore = ReceiptStore()
        let coordinator = WatchCaptureIngestCoordinator(
            inboxDirectory: directory, persistence: persistence,
            transcriber: FakeTranscriber(),
            ingestTodo: { captureID, _, _ in WatchTodoResult(title: "整理录音", todoID: captureID) },
            sendReceipt: { receipt in await receiptStore.append(receipt) }
        )
        try await coordinator.enqueue(fileURL: url, metadata: metadata)
        try await coordinator.enqueue(fileURL: url, metadata: metadata)
        let receipts = await receiptStore.values
        XCTAssertEqual(receipts.filter { if case .todoAdded = $0.status { true } else { false } }.count, 2)
        let pending = try await persistence.pending()
        XCTAssertEqual(pending.count, 0)
    }
}

private struct FakeTranscriber: WatchAudioTranscribing {
    func transcribe(fileURL: URL) async throws -> WatchTranscribedCapture { WatchTranscribedCapture(rawTranscript: "请整理录音") }
}

private actor ReceiptStore {
    var values: [WatchCaptureReceipt] = []
    func append(_ receipt: WatchCaptureReceipt) { values.append(receipt) }
}
