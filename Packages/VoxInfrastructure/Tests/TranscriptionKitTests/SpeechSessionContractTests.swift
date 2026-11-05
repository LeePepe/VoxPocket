import Foundation
import Synchronization
import VoxCore
import XCTest
@testable import TranscriptionKit
#if os(iOS)
import AVFoundation
#endif

final class SpeechSessionContractTests: XCTestCase {
    func testValueRelayBroadcastsOrderedCurrentValuesToEverySubscriber() async {
        let relay = AsyncValueRelay<Int>(0)
        let first = relay.stream()
        let second = relay.stream()
        for value in 1...100 { relay.send(value) }
        for stream in [first, second] {
            var received: [Int] = []
            for await value in stream {
                received.append(value)
                if value == 100 { break }
            }
            XCTAssertEqual(received, Array(0...100))
        }
    }

    func testValueRelayCanBroadcastWhileSubscribersAreCancelled() async {
        let relay = AsyncValueRelay<Int>(0)
        let completed = expectation(description: "concurrent cancellation completes")
        let stress = Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        let stream = relay.stream()
                        let observer = Task { for await _ in stream {} }
                        relay.send(1)
                        observer.cancel()
                        await observer.value
                    }
                }
            }
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
        stress.cancel()
    }

    func testSessionStreamsLevelsAndCancelPropagatesCancellation() async throws {
        let source = SessionContractSource()
        let session = try await source.startSession(language: .current)
        let level = expectation(description: "session level")
        let cancelled = expectation(description: "cancelled stream")
        let observer = Task {
            do {
                for try await event in session.events() {
                    if event == .level(0.75) { level.fulfill() }
                }
                XCTFail("Cancellation must terminate with an error")
            } catch is CancellationError { cancelled.fulfill() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        source.levels.send(0.75)
        await fulfillment(of: [level], timeout: 2)
        await session.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        observer.cancel()
        XCTAssertFalse(source.isActive)
    }

    func testDeviceInterruptionStopsAndPublishesSessionState() async throws {
        let source = SessionContractSource()
        let session = try await source.startSession(language: .current)
        let interrupted = expectation(description: "interrupted stream")
        let observer = Task {
            for try await event in session.events() {
                if event == .state(.interrupted) { interrupted.fulfill(); return }
            }
        }
        source.deviceStates.send(.interrupted)
        await fulfillment(of: [interrupted], timeout: 2)
        XCTAssertFalse(source.isActive)
        observer.cancel()
        await session.cancel()
    }

    func testSupersededSessionCannotControlTheNextRecording() async throws {
        let source = SessionContractSource()
        let first = try await source.startSession(language: .current)
        let second = try await source.startSession(language: .current)
        await first.pause()
        await first.resume()
        await first.stop()
        await first.cancel()
        XCTAssertEqual(source.operations.withLock { $0 }, ["start", "stop", "start"])
        XCTAssertTrue(source.isActive)
        await second.cancel()
        XCTAssertFalse(source.isActive)
    }

    func testDeniedMicrophonePermissionFailsBeforeAudioSessionOrDiskSetup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let recorder = MicrophoneRecorder(authorizationProvider: DeniedMicrophoneAuthorization(),
            storageLocations: VoxStorageLocations(temporaryAudio: directory, modelCache: directory))
        #if os(iOS)
        let category = AVAudioSession.sharedInstance().category
        #endif
        do {
            try await recorder.start(bufferHandler: nil)
            XCTFail("Denied permission must fail")
        } catch VoxKitError.microphoneAccessDenied {}
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        #if os(iOS)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, category)
        #endif
    }

}

private struct DeniedMicrophoneAuthorization: MicrophoneAuthorizationProviding {
    var hasMicrophoneAccess: Bool { false }
    func requestMicrophoneAccess() async -> Bool { false }
}

private final class SessionContractSource: SessionDriving {
    let sessionRelay = SpeechSessionRelay()
    let levels = AsyncValueRelay<Float>(0)
    let deviceStates = AsyncValueRelay<AudioCaptureState>(.idle)
    let operations = Mutex<[String]>([])
    private let capture = AsyncValueRelay<AudioCaptureState>(.idle)
    var providerKind: ASRProviderType { .custom }
    var supportedLanguages: [Locale] { [.current] }
    var isActive: Bool { capture.value == .recording }
    var hasMicrophonePermission: Bool { true }
    var hasSpeechPermission: Bool { true }
    func requestMicrophonePermission() async -> Bool { true }
    func requestSpeechPermission() async -> Bool { true }
    func captureStates() -> AsyncStream<AudioCaptureState> { capture.stream() }
    func captureDeviceStates() -> AsyncStream<AudioCaptureState> { deviceStates.stream() }
    func audioLevels() -> AsyncStream<Float> { levels.stream() }
    func start(language: Locale) async throws {
        operations.withLock { $0.append("start") }
        capture.send(.recording)
        sessionRelay.send(.state(.recording))
    }
    func pause() async { operations.withLock { $0.append("pause") } }
    func resume() async { operations.withLock { $0.append("resume") } }
    func stop() async {
        operations.withLock { $0.append("stop") }
        capture.send(.idle)
        sessionRelay.send(.state(.idle))
    }
}

let testStorageLocations = VoxStorageLocations(temporaryAudio: FileManager.default.temporaryDirectory, modelCache: FileManager.default.temporaryDirectory)
