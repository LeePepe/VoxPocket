import XCTest
import Synchronization
@testable import VoxPocketKit

final class WatchAudioLifecycleTests: XCTestCase {
    func testPermissionCallbackCompletesOnceAndMissingCallbackTimesOut() async {
        let permission = await WatchAudioPermissionRequest().value { completion in completion(true); completion(false) }
        XCTAssertTrue(permission)
        let timedOut = await WatchAudioPermissionRequest().value(timeout: .milliseconds(10)) { _ in }
        XCTAssertFalse(timedOut)
    }
    func testPermissionRequestCancellationReturnsWithoutWaitingForSystemCallback() async {
        let started = expectation(description: "permission request started")
        let task = Task { await WatchAudioPermissionRequest().value { _ in started.fulfill() } }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result)
    }
    func testRecordingConfigurationMeterDurationStopAndOverwriteProtection() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let backend = FakeAudioBackend()
        let service = WatchAudioCaptureService(storageURL: folder, backend: backend)
        let id = UUID()
        try await service.start(captureID: id)
        let stream = await service.levels(for: id)
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()!
        let second = try await iterator.next()!
        XCTAssertEqual(first.captureID, id)
        XCTAssertGreaterThan(second.elapsed, first.elapsed)
        XCTAssertEqual(second.normalizedLevel, 1)
        let capture = try await service.stop()
        XCTAssertGreaterThanOrEqual(capture.duration, second.elapsed)
        let finished = try await iterator.next()
        XCTAssertNil(finished)
        XCTAssertEqual(backend.configuration?.sampleRate, 16_000)
        XCTAssertEqual(backend.configuration?.channels, 1)
        XCTAssertEqual(backend.configuration?.format, "aac")
        let original = try Data(contentsOf: capture.fileURL)
        do { try await service.start(captureID: id); XCTFail("Must not overwrite retained audio") } catch {}
        XCTAssertEqual(try Data(contentsOf: capture.fileURL), original)
        try await service.start(captureID: UUID())
        await service.cancel()
    }
    func testPermissionFailureRecoversAndCancelFinishesStream() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let backend = FakeAudioBackend()
        backend.permission = false
        let service = WatchAudioCaptureService(storageURL: folder, backend: backend)
        do { try await service.start(captureID: UUID()); XCTFail("Permission must fail") }
        catch { XCTAssertEqual(error as? WatchCaptureError, .permissionDenied) }
        backend.permission = true
        let id = UUID(); try await service.start(captureID: id)
        var iterator = await service.levels(for: id).makeAsyncIterator()
        await service.cancel()
        let finished = try await iterator.next()
        XCTAssertNil(finished)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(id.uuidString).m4a").path))
    }
    func testMeterErrorPropagatesAndFiniteCaptureEndsSampling() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let backend = FakeAudioBackend()
        let service = WatchAudioCaptureService(storageURL: folder, backend: backend, maximumDuration: 0.2)
        let id = UUID(); try await service.start(captureID: id)
        backend.power = .nan
        var values: [WatchAudioLevel] = []
        for try await value in await service.levels(for: id) { values.append(value) }
        XCTAssertTrue(values.allSatisfy { $0.normalizedLevel == 0 && $0.elapsed.isFinite })
        let capture = try await service.stop()
        XCTAssertEqual(capture.duration, 0.2, accuracy: 0.01)
        let next = UUID(); try await service.start(captureID: next)
        backend.failMeter = true
        do { for try await _ in await service.levels(for: next) {}; XCTFail("Meter error must propagate") }
        catch { XCTAssertEqual(error as? WatchCaptureError, .captureFailed) }
        backend.failMeter = false
        try await service.start(captureID: UUID()); await service.cancel()
    }
}

private final class FakeAudioBackend: WatchAudioRecorderBackend, Sendable {
    private struct State {
        var permission = true
        var power: Float = 2
        var failMeter = false
        var url: URL?
        var configuration: WatchAudioRecordingConfiguration?
    }
    private let state = Mutex(State())
    var permission: Bool { get { state.withLock { $0.permission } } set { state.withLock { $0.permission = newValue } } }
    var power: Float { get { state.withLock { $0.power } } set { state.withLock { $0.power = newValue } } }
    var failMeter: Bool { get { state.withLock { $0.failMeter } } set { state.withLock { $0.failMeter = newValue } } }
    var configuration: WatchAudioRecordingConfiguration? { state.withLock { $0.configuration } }
    func requestPermission() async -> Bool { permission }
    func start(url: URL, configuration: WatchAudioRecordingConfiguration) throws {
        try Data(repeating: 7, count: 32).write(to: url)
        state.withLock { $0.url = url; $0.configuration = configuration }
    }
    func stop() throws {}
    func cancel() { if let url = state.withLock({ $0.url }) { try? FileManager.default.removeItem(at: url) } }
    func currentPower() throws -> Float { try state.withLock { if $0.failMeter { throw WatchCaptureError.captureFailed }; return $0.power } }
}
