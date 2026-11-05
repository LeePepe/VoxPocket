import AVFoundation
import Combine
import XCTest
@testable import TranscriptionKit

final class SpeechGoldenTraceTests: XCTestCase {
    func testAuthorizationAndRecorderSeamsAreDeterministic() async {
        let recorder = GoldenAudioSource(permission: false)
        let initiallyAllowed = await recorder.requestPermission()
        XCTAssertFalse(initiallyAllowed)
        XCTAssertFalse(recorder.hasPermission)
        recorder.permission = true
        let eventuallyAllowed = await recorder.requestPermission()
        XCTAssertTrue(eventuallyAllowed)
        XCTAssertTrue(recorder.hasPermission)
    }

    func testGoldenFixtureContract() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "golden_c_speech", withExtension: "json", subdirectory: "Fixtures"))
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(payload["schema"] as? String, "golden-trace/v1")
        XCTAssertEqual(payload["kind"] as? String, "speech")
    }
}

private final class GoldenAudioSource: AudioBufferSource, @unchecked Sendable {
    let levels = CurrentValueSubject<Float, Never>(0)
    let states = CurrentValueSubject<AudioCaptureState, Never>(.idle)
    var permission: Bool
    init(permission: Bool) { self.permission = permission }
    var audioLevelPublisher: AnyPublisher<Float, Never> { levels.eraseToAnyPublisher() }
    var statePublisher: AnyPublisher<AudioCaptureState, Never> { states.eraseToAnyPublisher() }
    var state: AudioCaptureState { states.value }
    func requestPermission() async -> Bool { permission }
    var hasPermission: Bool { permission }
    func start(bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws { states.send(.recording) }
    func startIfAllowed(shouldStart: @escaping @Sendable () -> Bool, bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws {
        guard shouldStart() else { throw CancellationError() }
        try await start(bufferHandler: bufferHandler)
    }
    func pause() { states.send(.paused) }
    func resume() { states.send(.recording) }
    func stop() -> URL? { states.send(.idle); return nil }
}
