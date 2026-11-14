import Foundation
import Combine
import Synchronization
import UseCases
import VoxCore

actor RecorderTestGate {
    private var entries = 0
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            entries += 1
            blocked.append(continuation)
            let ready = observers.filter { $0.0 <= entries }
            observers.removeAll { $0.0 <= entries }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForEntries(_ count: Int = 1) async {
        if entries >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func releaseNext() {
        if !blocked.isEmpty { blocked.removeFirst().resume() }
    }
}

final class ControlledRecordingUseCase: RecordingUseCase, Sendable {
    struct State {
        var recording: RecordingState = .idle
        var events: [String] = []
        let publisher = CurrentValueSubject<RecordingState, Never>(.idle)
        let levels = CurrentValueSubject<Float, Never>(0)
    }
    private let storage = Mutex(State())
    let gate: RecorderTestGate
    let failsStart: Bool

    init(gate: RecorderTestGate, failsStart: Bool = false) {
        self.gate = gate
        self.failsStart = failsStart
    }
    var events: [String] { storage.withLock { $0.events } }
    var state: RecordingState { storage.withLock { $0.recording } }
    var statePublisher: AnyPublisher<RecordingState, Never> { storage.withLock { $0.publisher.eraseToAnyPublisher() } }
    var audioLevelPublisher: AnyPublisher<Float, Never> { storage.withLock { $0.levels.eraseToAnyPublisher() } }

    func startRecording() async throws {
        storage.withLock { $0.events.append("start-requested") }
        await gate.suspend()
        if failsStart { throw NSError(domain: "synthetic-start", code: 1) }
        // 有意不发送状态事件，验证 await 返回不依赖下一次主队列发布。
        storage.withLock { $0.recording = .recording(duration: 1); $0.events.append("started") }
    }
    func stopRecording() async throws {
        storage.withLock { $0.events.append($0.recording.isActive ? "stopped" : "invalid-stop"); $0.recording = .idle }
    }
    func cancelRecording() { storage.withLock { $0.events.append("cancelled"); $0.recording = .idle } }
    func pauseRecording() {}
    func resumeRecording() {}
    func checkPermission() async -> Bool { true }
    func requestPermission() async -> Bool { true }
}

final class WorkspaceTranscriptionProbe: TranscriptionUseCase, Sendable {
    struct State {
        let live = PassthroughSubject<String, Never>()
        let final = PassthroughSubject<TranscriptionResult, Error>()
        var snapshotGateActive = false
    }
    private let storage = Mutex(State())
    var liveTextPublisher: AnyPublisher<String, Never> { storage.withLock { $0.live.eraseToAnyPublisher() } }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { storage.withLock { $0.final.eraseToAnyPublisher() } }
    var currentLanguage: Locale { Locale(identifier: "zh-Hans") }
    var supportedLanguages: [Locale] { [currentLanguage] }
    var snapshotPublisher: AnyPublisher<String, Never> { liveTextPublisher }
    var snapshotGateActive: Bool {
        get { storage.withLock { $0.snapshotGateActive } }
        set { storage.withLock { $0.snapshotGateActive = newValue } }
    }
    func send(_ text: String) { storage.withLock { $0.live }.send(text) }
    func clearLiveText() { send("") }
    func setLanguage(_ locale: Locale) {}
    func commitCurrentTranscription() async throws {}
}
