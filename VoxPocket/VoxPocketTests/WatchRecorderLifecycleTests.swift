import XCTest
import Combine
import VoxPocketKit

@MainActor
final class WatchRecorderLifecycleTests: XCTestCase {
    func testRetryResendsOriginalBytesAndAllowsSecondCaptureAfterSuccess() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = ModelFakeWatchRecorder(directory: folder)
        let transport = ModelFakeWatchTransport()
        let bridge = VoxWatchSyncBridge(transport: transport, storageDirectory: folder)
        let model = WatchRecorderViewModel(recorder: recorder, bridge: bridge)
        let firstStart = model.start()
        XCTAssertTrue(model.actionLocked)
        XCTAssertNil(model.start(), "Action Button start must be idempotent")
        await firstStart?.value
        XCTAssertEqual(model.state, .recording)
        let stop = model.stop()
        XCTAssertTrue(model.actionLocked)
        XCTAssertNil(model.stop(), "Double tap must not submit twice")
        await stop?.value
        let ids = await recorder.ids
        let id = try XCTUnwrap(ids.first)
        let file = folder.appendingPathComponent("\(id.uuidString).m4a")
        let bytes = try Data(contentsOf: file)
        model.apply(WatchCaptureReceipt(captureID: id, status: .failed(captureID: id, reason: "失败")))
        XCTAssertTrue(model.canRetry)
        await model.retry()?.value
        let startsAfterRetry = await recorder.ids
        XCTAssertEqual(startsAfterRetry, [id], "Retry must NEVER restart the mic with this UUID")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        model.apply(WatchCaptureReceipt(captureID: id, status: .todoAdded(captureID: id, title: "整理纪要", todoID: UUID())))
        XCTAssertEqual(model.state, .success("整理纪要"))
        XCTAssertFalse(model.canRetry)
        model.apply(WatchCaptureReceipt(captureID: id, status: .processingOnPhone))
        model.apply(WatchCaptureReceipt(captureID: UUID(), status: .transferring))
        XCTAssertEqual(model.state, .success("整理纪要"))
        await model.start()?.value
        let nextIDs = await recorder.ids
        XCTAssertEqual(nextIDs.count, 2); XCTAssertNotEqual(nextIDs[0], nextIDs[1])
        XCTAssertEqual(model.state, .recording)
        model.apply(WatchCaptureReceipt(captureID: id, status: .todoAdded(captureID: id, title: "整理纪要", todoID: UUID())))
        XCTAssertEqual(model.state, .recording)
        await model.stop()?.value
    }
    func testIntentBeforeRuntimeInstallStartsOnceAndForeignURLDoesNotRecord() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = ModelFakeWatchRecorder(directory: folder)
        let model = WatchRecorderViewModel(recorder: recorder, bridge: VoxWatchSyncBridge(transport: ModelFakeWatchTransport(), storageDirectory: folder))
        let recording = expectation(description: "deferred intent starts actual model")
        let subscription = model.$state.filter { $0 == .recording }.first().sink { _ in recording.fulfill() }
        defer { subscription.cancel() }
        WatchRecordingRuntime.start()
        WatchRecordingRuntime.start()
        WatchRecordingRuntime.install { model.start() }
        await fulfillment(of: [recording], timeout: 2)
        WatchRecordingRuntime.start()
        WatchRecordingRuntime.open(URL(string: "voxpocket-watch://record")!)
        WatchRecordingRuntime.open(URL(string: "https://example.invalid/record")!)
        let ids = await recorder.ids
        XCTAssertEqual(ids.count, 1); XCTAssertEqual(model.state, .recording)
        await model.stop()?.value
        WatchRecordingRuntime.open(URL(string: "https://example.invalid/record")!)
        WatchRecordingRuntime.open(URL(string: "voxpocket-watch://record?path=other")!)
        XCTAssertEqual(model.state, .transferring, "Untrusted app-open routes must not start the mic")
        let opened = expectation(description: "complication app-open starts next capture")
        let nextSubscription = model.$state.filter { $0 == .recording }.first().sink { _ in opened.fulfill() }
        defer { nextSubscription.cancel() }
        WatchRecordingRuntime.open(URL(string: "voxpocket-watch://record")!)
        await fulfillment(of: [opened], timeout: 2)
        let nextIDs = await recorder.ids
        XCTAssertEqual(nextIDs.count, 2); XCTAssertNotEqual(nextIDs[0], nextIDs[1])
        await model.stop()?.value
    }
    func testPermissionFailureDoesNotBrickPrimaryActionOrOfferUnrecoverableRetry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = ModelFakeWatchRecorder(directory: folder)
        await recorder.failNextStart()
        let model = WatchRecorderViewModel(recorder: recorder, bridge: VoxWatchSyncBridge(transport: ModelFakeWatchTransport(), storageDirectory: folder))
        await model.start()?.value
        XCTAssertFalse(model.canRetry)
        XCTAssertNil(model.retry())
        await model.start()?.value
        XCTAssertEqual(model.state, .recording)
        await model.stop()?.value
    }

    func testEarlierSubmittedCaptureFailureRemainsRetryableAfterSecondCaptureStarts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = ModelFakeWatchRecorder(directory: folder)
        let bridge = VoxWatchSyncBridge(transport: ModelFakeWatchTransport(), storageDirectory: folder)
        let model = WatchRecorderViewModel(recorder: recorder, bridge: bridge)

        await model.start()?.value
        await model.stop()?.value
        await model.start()?.value
        await model.stop()?.value
        let ids = await recorder.ids
        XCTAssertEqual(ids.count, 2)
        let firstID = ids[0]
        let secondID = ids[1]

        // First capture fails before second capture finishes; then second capture succeeds.
        model.apply(WatchCaptureReceipt(captureID: firstID, status: .failed(captureID: firstID, reason: "失败")))
        model.apply(WatchCaptureReceipt(captureID: secondID, status: .todoAdded(captureID: secondID, title: "第二条待办", todoID: UUID())))
        XCTAssertEqual(model.state, .success("第二条待办"))
        XCTAssertTrue(model.canRetry, "Earlier retained failed capture must remain retryable even while showing latest success")

        await model.retry()?.value
        let startsAfterRetry = await recorder.ids
        XCTAssertEqual(startsAfterRetry.count, 2)
        XCTAssertEqual(model.lastReceipt?.captureID, firstID)
    }
}
private actor ModelFakeWatchRecorder: WatchAudioCapturing {
    let directory: URL
    var ids: [UUID] = []
    var active: UUID?
    var fails = false
    var continuation: AsyncThrowingStream<WatchAudioLevel, Error>.Continuation?
    init(directory: URL) { self.directory = directory }
    func failNextStart() { fails = true }
    func start(captureID: UUID) throws {
        if fails { fails = false; throw WatchCaptureError.permissionDenied }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 32).write(to: directory.appendingPathComponent("\(captureID.uuidString).m4a"))
        ids.append(captureID); active = captureID
    }
    func stop() throws -> WatchAudioCapture {
        let id = try XCTUnwrap(active); active = nil; continuation?.finish()
        return WatchAudioCapture(captureID: id, fileURL: directory.appendingPathComponent("\(id.uuidString).m4a"), duration: 2)
    }
    func cancel() { active = nil; continuation?.finish() }
    func levels(for captureID: UUID) -> AsyncThrowingStream<WatchAudioLevel, Error> {
        AsyncThrowingStream { continuation = $0 }
    }
}
private actor ModelFakeWatchTransport: WatchSyncTransport {
    var isReachable: Bool { get async { false } }
    func activate() async {}
    func transferFile(_ url: URL, metadata: WatchCaptureMetadata) async throws {}
    func transferReceipt(_ receipt: WatchCaptureReceipt) async throws {}
    func receipts() async -> AsyncStream<WatchCaptureReceipt> { AsyncStream { $0.finish() } }
}
