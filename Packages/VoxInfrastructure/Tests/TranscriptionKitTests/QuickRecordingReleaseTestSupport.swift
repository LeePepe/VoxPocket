import Foundation
import Synchronization
@testable import TranscriptionKit

actor QuickRecordingEffectGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observers.forEach { $0.resume() }; observers.removeAll()
        }
    }

    func entered() async {
        if continuation != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func release() { continuation?.resume(); continuation = nil }
}

final class QuickRecordingEffectProbe: Sendable {
    struct State {
        var callbacks: [(UUID, QuickRecordingSessionEffects.ResultHandler)] = []
        var events: [String] = []
    }
    let state = Mutex(State())
    let startGate: QuickRecordingEffectGate?
    let cleanupGate: QuickRecordingEffectGate?
    let earlyResult: TranscriptionResult?
    let cleanupFails: Bool
    let startFails: Bool
    let realtime: Bool

    init(startGate: QuickRecordingEffectGate? = nil, cleanupGate: QuickRecordingEffectGate? = nil,
         earlyResult: TranscriptionResult? = nil, cleanupFails: Bool = false, realtime: Bool = false,
         startFails: Bool = false) {
        self.startGate = startGate; self.cleanupGate = cleanupGate
        self.earlyResult = earlyResult; self.cleanupFails = cleanupFails; self.realtime = realtime
        self.startFails = startFails
    }

    var effects: QuickRecordingSessionEffects {
        QuickRecordingSessionEffects(start: { [self] id, _, callback in
            state.withLock { $0.callbacks.append((id, callback)); $0.events.append("start") }
            if let earlyResult { callback(earlyResult) }
            await startGate?.wait()
            if startFails { throw QuickRecordingReleaseError.unsupported }
        }, stopCapture: { [self] in
            record("stop"); return URL(fileURLWithPath: "/example-recording.wav")
        }, endAppleAudio: { [self] in record("endApple") }, cancelApple: { [self] in
            record("cancelApple")
        }, cancelRealtime: { [self] in record("cancelRealtime") }, removeAudio: { [self] _ in
            record("removeAudio")
            await cleanupGate?.wait()
            if cleanupFails { throw QuickRecordingReleaseError.unsupported }
        }, finalize: { [self] _ in
            if realtime { record("realtimeFinish"); record("commit") }
            else { record("batch") }
            return "synthetic final"
        })
    }

    func record(_ event: String) { state.withLock { $0.events.append(event) } }
    func count(_ event: String) -> Int { state.withLock { $0.events.filter { $0 == event }.count } }
    var sessionID: UUID { state.withLock { $0.callbacks.last!.0 } }

    func send(_ text: String, type: TranscriptionResultType = .partial, index: Int? = nil) {
        let callback = state.withLock { $0.callbacks[index ?? ($0.callbacks.count - 1)].1 }
        callback(.init(text: text, type: type, locale: .current))
    }
}

enum QuickRecordingTestProvider: CaseIterable {
    case apple, batch, realtime

    func make(_ probe: QuickRecordingEffectProbe) -> any TranscriptionCoordinator & QuickRecordingReleaseControlling {
        if self == .apple { return AppleSpeechTranscriber(effects: probe.effects) }
        let config = AzureWhisperConfig(endpoint: URL(string: "https://example.invalid/transcriptions")!, apiKey: "fixture")
        return HybridWhisperTranscriber(whisperConfig: config, effects: probe.effects)
    }
}

final class QuickRecordingCountingMerger: TranscriptionMerger {
    let calls = Mutex(0)
    func merge(appleSpeech: String, whisper: String) async throws -> String {
        calls.withLock { $0 += 1 }
        return "synthetic merged"
    }
}

actor QuickRecordingClosingTransport: RealtimeTranscriptionTransport {
    let closing = QuickRecordingEffectGate()
    private(set) var closes = 0
    func connect(request: URLRequest) async throws {}
    func send(_ data: Data) async throws {}
    func receive() async throws -> Data { throw CancellationError() }
    func close() async { closes += 1; await closing.wait() }
}
