import XCTest
@testable import Observability

final class TelemetryQueueTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetryQueueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    // MARK: - In-memory

    func testEnqueueAndTake() async {
        let q = TelemetryQueue(storeDirectory: tmpDir)

        let e1 = TelemetryEvent(name: "a", properties: ["k": "v"])
        let e2 = TelemetryEvent(name: "b")

        await q.enqueue(e1)
        await q.enqueue(e2)

        let taken = await q.takePendingEvents()
        XCTAssertEqual(taken.count, 2)
        XCTAssertEqual(taken[0].name, "a")
        XCTAssertEqual(taken[1].name, "b")
    }

    func testTakeClearsBuffer() async {
        let q = TelemetryQueue(storeDirectory: tmpDir)

        await q.enqueue(TelemetryEvent(name: "x"))
        _ = await q.takePendingEvents()

        let second = await q.takePendingEvents()
        XCTAssertTrue(second.isEmpty)
    }

    func testPendingCount() async {
        let q = TelemetryQueue(storeDirectory: tmpDir)

        let count0 = await q.pendingCount
        XCTAssertEqual(count0, 0)
        await q.enqueue(TelemetryEvent(name: "x"))
        let count1 = await q.pendingCount
        XCTAssertEqual(count1, 1)
        await q.enqueue(TelemetryEvent(name: "y"))
        let count2 = await q.pendingCount
        XCTAssertEqual(count2, 2)
    }

    // MARK: - Disk persistence

    func testPersistAndLoad() async throws {
        let q = TelemetryQueue(storeDirectory: tmpDir)

        let events = [
            TelemetryEvent(name: "transcription.completed", properties: ["duration_ms": "1234"]),
            TelemetryEvent(name: "refinement.completed", properties: ["duration_ms": "567"])
        ]

        let id = UUID()
        try await q.persistBatch(id: id, events: events)

        let loaded = try await q.loadPersistedBatches()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, id)
        XCTAssertEqual(loaded[0].events.count, 2)
        XCTAssertEqual(loaded[0].events[0].name, "transcription.completed")
        XCTAssertEqual(loaded[0].events[0].properties["duration_ms"], "1234")
    }

    func testRemoveBatch() async throws {
        let q = TelemetryQueue(storeDirectory: tmpDir)

        let id = UUID()
        try await q.persistBatch(id: id, events: [TelemetryEvent(name: "x")])
        try await q.removeBatch(id: id)

        let loaded = try await q.loadPersistedBatches()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLoadNonExistentDirectory() async throws {
        let noDir = tmpDir.appendingPathComponent("does-not-exist", isDirectory: true)
        let q = TelemetryQueue(storeDirectory: noDir)

        let loaded = try await q.loadPersistedBatches()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testPersistRoundtripPreservesAllFields() async throws {
        let q = TelemetryQueue(storeDirectory: tmpDir)

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let event = TelemetryEvent(
            name: "test.event",
            properties: ["duration_ms": "999", "provider": "appleIntelligence"],
            timestamp: fixedDate
        )

        let id = UUID()
        try await q.persistBatch(id: id, events: [event])

        let loaded = try await q.loadPersistedBatches()
        let loadedEvent = try XCTUnwrap(loaded.first?.events.first)

        XCTAssertEqual(loadedEvent.name, event.name)
        XCTAssertEqual(loadedEvent.properties["duration_ms"], "999")
        XCTAssertEqual(loadedEvent.properties["provider"], "appleIntelligence")
        XCTAssertEqual(
            loadedEvent.timestamp.timeIntervalSince1970,
            event.timestamp.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testMultipleBatchesLoadedInOrder() async throws {
        let q = TelemetryQueue(storeDirectory: tmpDir)

        let id1 = UUID()
        let id2 = UUID()
        try await q.persistBatch(id: id1, events: [TelemetryEvent(name: "first")])
        // Small sleep to ensure different creation timestamps
        try await Task.sleep(for: .milliseconds(10))
        try await q.persistBatch(id: id2, events: [TelemetryEvent(name: "second")])

        let loaded = try await q.loadPersistedBatches()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].events[0].name, "first")
        XCTAssertEqual(loaded[1].events[0].name, "second")
    }
}
