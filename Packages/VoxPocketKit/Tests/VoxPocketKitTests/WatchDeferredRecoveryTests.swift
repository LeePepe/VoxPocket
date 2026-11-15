import XCTest
@testable import VoxPocketKit

final class WatchDeferredRecoveryTests: XCTestCase {
    func testCancellationKeepsDurableJobForForegroundRelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID(), url = folder.appendingPathComponent("\(id.uuidString).m4a")
        try Data(repeating: 3, count: 32).write(to: url)
        let metadata = try WatchCaptureMetadata(captureID: id, duration: 1, basename: url.lastPathComponent)
        let persistence = FileWatchIngestPersistence(directory: folder.appendingPathComponent("state"))
        let started = expectation(description: "transcription started")
        let coordinator = WatchCaptureIngestCoordinator(inboxDirectory: folder, persistence: persistence,
            transcriber: SuspendedWatchTranscriber(started: started),
            ingestTodo: { _, _, _ in XCTFail("Cancelled work must not ingest"); throw CancellationError() }, sendReceipt: { _ in })
        let task = Task { try await coordinator.enqueue(fileURL: url, metadata: metadata) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { try await task.value; XCTFail("Expiration must cancel processing") } catch {}
        let reopened = FileWatchIngestPersistence(directory: folder.appendingPathComponent("state"))
        let pending = try await reopened.pending(), completion = try await reopened.completion(for: id)
        XCTAssertEqual(pending, [metadata]); XCTAssertNil(completion)
        let success = expectation(description: "foreground resumed persisted job")
        let resumed = WatchCaptureIngestCoordinator(inboxDirectory: folder, persistence: reopened,
            transcriber: ResumedWatchTranscriber(), ingestTodo: { _, _, _ in WatchTodoResult(title: "整理纪要", todoID: id) },
            sendReceipt: { receipt in if case .todoAdded = receipt.status { success.fulfill() } })
        await resumed.resume { _ in url }
        await fulfillment(of: [success], timeout: 2)
        let remaining = try await reopened.pending()
        XCTAssertTrue(remaining.isEmpty)
    }
    func testLegacyJournalMigratesPendingAndOnlySuccessfulReceipts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID(), metadata = try WatchCaptureMetadata(captureID: id, duration: 2, basename: "\(id.uuidString).m4a")
        let successID = UUID(), failureID = UUID()
        let success = WatchCaptureReceipt(captureID: successID, status: .todoAdded(captureID: successID, title: "整理纪要", todoID: UUID()))
        let failure = WatchCaptureReceipt(captureID: failureID, status: .failed(captureID: failureID, reason: "重试"))
        struct Legacy: Codable { let pending: [WatchCaptureMetadata]; let completions: [WatchCaptureReceipt] }
        try JSONEncoder().encode(Legacy(pending: [metadata], completions: [success, failure])).write(to: folder.appendingPathComponent("watch-state.json"))
        let persistence = FileWatchIngestPersistence(directory: folder)
        let pending = try await persistence.pending(), cachedSuccess = try await persistence.completion(for: successID), cachedFailure = try await persistence.completion(for: failureID)
        XCTAssertEqual(pending, [metadata]); XCTAssertEqual(cachedSuccess, success); XCTAssertNil(cachedFailure)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("watch-state.json"))
        let reopened = FileWatchIngestPersistence(directory: folder)
        let durablePending = try await reopened.pending()
        XCTAssertEqual(durablePending, [metadata])
    }
    func testSenderRecoversAudioCopiedBeforeQueueJournalCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), metadata = try WatchCaptureMetadata(captureID: id, duration: 2, basename: "\(id.uuidString).m4a")
        try JSONEncoder().encode(metadata).write(to: root.appendingPathComponent("\(id.uuidString).capture.json"))
        try Data(repeating: 5, count: 32).write(to: root.appendingPathComponent(metadata.basename))
        let transport = FakeTransport()
        let bridge = VoxWatchSyncBridge(transport: transport, storageDirectory: root)
        let captures = try await bridge.retainedCaptures()
        XCTAssertEqual(captures.map(\.captureID), [id])
        XCTAssertEqual(captures.first?.duration, 2)
        await transport.setReachable(true)
        try await bridge.activate()
        let transfers = await transport.transfers
        XCTAssertEqual(transfers, [id])
    }
    func testInterruptedPartialCopyIsNotRecoveredAndRetryClaimsFullAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = WatchInboxStore(directory: root.appendingPathComponent("inbox"))
        let id = UUID(), metadata = try WatchCaptureMetadata(captureID: id, duration: 1, basename: "\(id.uuidString).m4a")
        let staging = inbox.directory.appendingPathComponent("\(id.uuidString).staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try JSONEncoder().encode(metadata).write(to: staging.appendingPathComponent("metadata.json"))
        try Data(repeating: 1, count: 4).write(to: staging.appendingPathComponent("interrupted.part"))
        XCTAssertTrue(try inbox.recover().isEmpty)
        let source = root.appendingPathComponent("input.m4a")
        let bytes = Data(repeating: 2, count: 32)
        try bytes.write(to: source)
        let owned = try inbox.claim(source, metadata: metadata)
        XCTAssertEqual(try Data(contentsOf: owned), bytes)
        XCTAssertEqual(try inbox.recover().first?.1, metadata)
    }
}
private struct SuspendedWatchTranscriber: WatchAudioTranscribing {
    let started: XCTestExpectation
    func transcribe(fileURL: URL) async throws -> WatchTranscribedCapture {
        started.fulfill()
        try await Task.sleep(for: .seconds(2))
        return WatchTranscribedCapture(rawTranscript: "整理纪要")
    }
}
private struct ResumedWatchTranscriber: WatchAudioTranscribing {
    func transcribe(fileURL: URL) async throws -> WatchTranscribedCapture { WatchTranscribedCapture(rawTranscript: "整理纪要") }
}
