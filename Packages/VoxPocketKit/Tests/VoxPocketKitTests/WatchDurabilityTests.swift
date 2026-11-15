import XCTest
import CoreModels
@testable import VoxPocketKit

final class WatchDurabilityTests: XCTestCase {
    func testOfflineQueueSurvivesRelaunchAndDoesNotDuplicateOutstandingTransfer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID(), url = folder.appendingPathComponent("source.m4a")
        let audio = folder.appendingPathComponent("\(id.uuidString).m4a")
        try Data(repeating: 4, count: 32).write(to: audio)
        let transport = FakeTransport()
        let storage = folder.appendingPathComponent("sender")
        var original: VoxWatchSyncBridge? = VoxWatchSyncBridge(transport: transport, storageDirectory: storage)
        _ = try await original!.send(capture: WatchAudioCapture(captureID: id, fileURL: audio, duration: 1))
        original = nil
        let recovered = VoxWatchSyncBridge(transport: transport, storageDirectory: storage)
        let pending = try await recovered.retainedCaptures()
        XCTAssertEqual(pending.map(\.captureID), [id])
        XCTAssertEqual(try Data(contentsOf: pending[0].fileURL), Data(repeating: 4, count: 32))
        await transport.setReachable(true)
        try await recovered.activate()
        _ = try await recovered.send(capture: pending[0])
        try await recovered.activate()
        let transfers = await transport.transfers
        XCTAssertEqual(transfers, [id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testClaimCommitsJournalBeforeReturnDuplicateAndStagingRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), source = root.appendingPathComponent("input.m4a")
        try Data(repeating: 4, count: 32).write(to: source)
        let metadata = try WatchCaptureMetadata(captureID: id, duration: 1, basename: "\(id.uuidString).m4a")
        let store = WatchInboxStore(directory: root.appendingPathComponent("inbox"))
        let owned = try store.claim(source, metadata: metadata)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try store.recover().first?.0.standardizedFileURL, owned.standardizedFileURL)
        try Data(repeating: 9, count: 32).write(to: source)
        XCTAssertEqual(try store.claim(source, metadata: metadata), owned)
        XCTAssertEqual(try Data(contentsOf: owned), Data(repeating: 4, count: 32))
        let next = UUID()
        let staging = store.directory.appendingPathComponent("\(next.uuidString).staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let nextMetadata = try WatchCaptureMetadata(captureID: next, duration: 2, basename: "\(next.uuidString).m4a")
        try JSONEncoder().encode(nextMetadata).write(to: staging.appendingPathComponent("metadata.json"))
        try Data(repeating: 2, count: 16).write(to: staging.appendingPathComponent(nextMetadata.basename))
        let recovered = try WatchInboxStore(directory: store.directory).recover()
        XCTAssertEqual(Set(recovered.map { $0.1.captureID }), [id, next])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        let symlink = root.appendingPathComponent("link.m4a")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: owned)
        XCTAssertThrowsError(try store.claim(symlink, metadata: metadata))
    }
    func testPairedTransportFailureThenSameIDRetryCreatesActualWatchTodoAndOrdersReceipt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID(), audio = folder.appendingPathComponent("\(id.uuidString).m4a")
        try Data(repeating: 1, count: 32).write(to: audio)
        let transport = FakeTransport(), counter = IngestCounter(), transcriber = FlakyTranscriber()
        let inbox = WatchInboxStore(directory: folder.appendingPathComponent("inbox"))
        let persistence = FileWatchIngestPersistence(directory: folder.appendingPathComponent("state"))
        let coordinator = WatchCaptureIngestCoordinator(inboxDirectory: inbox.directory, persistence: persistence,
            transcriber: transcriber, ingestTodo: { _, text, metadata in
                let todo = VoiceTodo(title: text.rawTranscript, taskPrompt: text.rawTranscript, rawTranscript: text.rawTranscript,
                    localAudioFileName: metadata.basename, durationSeconds: metadata.duration, deviceSource: .appleWatch)
                await counter.append(todo)
                return WatchTodoResult(title: todo.title, todoID: todo.id)
            }, sendReceipt: { try await transport.transferReceipt($0) })
        await transport.setOnFile { url, metadata in try await coordinator.enqueue(fileURL: inbox.claim(url, metadata: metadata), metadata: metadata) }
        await transport.setReachable(true)
        let bridge = VoxWatchSyncBridge(transport: transport, storageDirectory: folder.appendingPathComponent("sender"), replayInterval: 0)
        try await bridge.activate()
        let failed = expectation(description: "failure delivered"), success = expectation(description: "success delivered")
        let observer = Task {
            var receivedFailure = false
            var receivedSuccess = false
            for await receipt in await bridge.receiveReceipts() {
                switch receipt.status {
                case .failed where !receivedFailure: receivedFailure = true; failed.fulfill()
                case .todoAdded where !receivedSuccess: receivedSuccess = true; success.fulfill()
                default: break
                }
            }
        }
        defer { observer.cancel() }
        let capture = WatchAudioCapture(captureID: id, fileURL: audio, duration: 1)
        _ = try await bridge.send(capture: capture)
        await fulfillment(of: [failed], timeout: 2)
        await transport.finishFile(id, succeeded: false)
        await transcriber.allowSuccess()
        _ = try await bridge.send(capture: capture)
        await fulfillment(of: [success], timeout: 2)
        let todos = await counter.todos
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos.first?.deviceSource, .appleWatch)
        XCTAssertEqual(todos.first?.localAudioFileName, capture.fileURL.lastPathComponent)
        let saved = try await persistence.completion(for: id)
        XCTAssertNotNil(saved)
        let pendingAfterSuccess = try await persistence.pending()
        XCTAssertTrue(pendingAfterSuccess.isEmpty)
        if let saved {
            XCTAssertFalse(WatchCaptureReceipt(captureID: id, status: .processingOnPhone).canFollow(saved))
            XCTAssertFalse(WatchCaptureReceipt(captureID: UUID(), status: .transferring).canFollow(saved))
        }
    }
}
private actor FlakyTranscriber: WatchAudioTranscribing {
    var fails = true
    func allowSuccess() { fails = false }
    func transcribe(fileURL: URL) throws -> WatchTranscribedCapture {
        if fails { throw WatchCaptureError.captureFailed }
        return WatchTranscribedCapture(rawTranscript: "整理录音")
    }
}
private actor IngestCounter {
    var todos: [VoiceTodo] = []
    func append(_ todo: VoiceTodo) { todos.append(todo) }
}
