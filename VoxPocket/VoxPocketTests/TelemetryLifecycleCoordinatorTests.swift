import Foundation
import LokiKit
import Synchronization
import Testing
@testable import VoxPocket

@MainActor
struct TelemetryLifecycleCoordinatorTests {
    @Test func providerWorkIsOrderedSerializedAndOffMain() async {
        let recorder = TelemetryOperationRecorder()
        let coordinator = TelemetryLifecycleCoordinator {
            recorder.perform("construct")
            return RecordingTelemetryService(recorder: recorder)
        }

        coordinator.track(name: "A", properties: [:])
        coordinator.track(name: "B", properties: [:])
        await coordinator.flush()

        #expect(recorder.names == ["construct", "track A", "track B", "flush"])
        #expect(recorder.maximumConcurrency == 1)
        #expect(recorder.mainThreadCalls == 0)
    }

    @Test func flushAfterInterveningAdmissionWaitsForASecondUnderlyingFlush() async {
        let recorder = TelemetryOperationRecorder()
        let gate = FlushGate()
        let coordinator = TelemetryLifecycleCoordinator {
            recorder.perform("construct")
            return RecordingTelemetryService(recorder: recorder, flushGate: gate)
        }

        coordinator.track(name: "A", properties: [:])
        let firstFlush = Task { await coordinator.flush() }
        await gate.waitUntilEntered()

        coordinator.track(name: "B", properties: [:])
        let laterFlush = Task { await coordinator.flush() }
        await Task.yield()
        #expect(recorder.names == ["construct", "track A", "flush"])

        await gate.open()
        await firstFlush.value
        await laterFlush.value

        #expect(recorder.names == ["construct", "track A", "flush", "track B", "flush"])
        #expect(recorder.maximumConcurrency == 1)
        #expect(recorder.mainThreadCalls == 0)
    }

    @Test func adjacentFlushJoinsTheActiveUnderlyingFlush() async {
        let recorder = TelemetryOperationRecorder()
        let gate = FlushGate()
        let coordinator = TelemetryLifecycleCoordinator {
            recorder.perform("construct")
            return RecordingTelemetryService(recorder: recorder, flushGate: gate)
        }

        coordinator.track(name: "A", properties: [:])
        let firstFlush = Task { await coordinator.flush() }
        await gate.waitUntilEntered()

        let joinedFlush = Task { await coordinator.flush() }
        await Task.yield()
        #expect(recorder.names == ["construct", "track A", "flush"])

        await gate.open()
        await firstFlush.value
        await joinedFlush.value

        #expect(recorder.names == ["construct", "track A", "flush"])
        #expect(recorder.maximumConcurrency == 1)
        #expect(recorder.mainThreadCalls == 0)
    }
}

private final class RecordingTelemetryService: TelemetryService, Sendable {
    private let state = Mutex(false)
    private let recorder: TelemetryOperationRecorder
    private let flushGate: FlushGate?

    var isEnabled: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    init(recorder: TelemetryOperationRecorder, flushGate: FlushGate? = nil) {
        self.recorder = recorder
        self.flushGate = flushGate
    }

    func track(_ event: TelemetryEvent) {
        recorder.perform("track \(event.name)")
    }

    func track(name: String, properties: [String: String]) {
        recorder.perform("track \(name)")
    }

    func flush() async {
        recorder.begin("flush")
        if let flushGate {
            await flushGate.enter()
        }
        recorder.end()
    }

    func resetIdentifier() {
        recorder.perform("reset")
    }
}

private final class TelemetryOperationRecorder: Sendable {
    private struct State: Sendable {
        var names: [String] = []
        var currentConcurrency = 0
        var maximumConcurrency = 0
        var mainThreadCalls = 0
        var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    }

    private let state = Mutex(State())

    var names: [String] {
        state.withLock { $0.names }
    }

    var maximumConcurrency: Int {
        state.withLock { $0.maximumConcurrency }
    }

    var mainThreadCalls: Int {
        state.withLock { $0.mainThreadCalls }
    }

    func perform(_ name: String) {
        begin(name)
        end()
    }

    func begin(_ name: String) {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.names.append(name)
            state.currentConcurrency += 1
            state.maximumConcurrency = max(state.maximumConcurrency, state.currentConcurrency)
            if Thread.isMainThread {
                state.mainThreadCalls += 1
            }
            return state.waiters.removeValue(forKey: name) ?? []
        }
        waiters.forEach { $0.resume() }
    }

    func end() {
        state.withLock { $0.currentConcurrency -= 1 }
    }

    func waitUntilRecorded(_ name: String) async {
        guard !names.contains(name) else { return }
        await withCheckedContinuation { continuation in
            let alreadyRecorded = state.withLock { state -> Bool in
                guard !state.names.contains(name) else { return true }
                state.waiters[name, default: []].append(continuation)
                return false
            }
            if alreadyRecorded {
                continuation.resume()
            }
        }
    }
}

private actor FlushGate {
    private var entered = false
    private var opened = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        guard !opened else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        opened = true
        openWaiters.forEach { $0.resume() }
        openWaiters.removeAll()
    }
}
