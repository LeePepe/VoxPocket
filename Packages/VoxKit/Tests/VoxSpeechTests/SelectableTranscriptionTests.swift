import VoxCore
import Foundation
import Synchronization
import XCTest
@testable import VoxSpeech

final class SelectableTranscriptionTests: XCTestCase {
    func testQuickReleaseBeforeRouterStartNeverRunsSelection() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.apple.make(probe)
        let selections = Mutex(0)
        let router = makeSelectableCoordinator(permissionCoordinator: source) {
            selections.withLock { $0 += 1 }; return source
        }
        try router.prepareQuickRecording()
        let frozen = try router.freezeQuickRecordingRelease()
        do { try await router.start(language: .current); XCTFail("Released startup must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await router.completeQuickRecordingRelease(frozen)
        XCTAssertEqual(selections.withLock { $0 }, 0)
        XCTAssertEqual(probe.count("start"), 0)
        try router.prepareQuickRecording()
    }

    func testEligibleQuickAppleRetainsFinalAndOldRouterTokenCannotStopNextSession() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.apple.make(probe)
        let router = makeSelectableCoordinator(permissionCoordinator: source) { source }
        let finals = Mutex(0)
        let subscription = router.observeFinals({ _ in
            finals.withLock { $0 += 1 }
        })
        defer { subscription.cancel() }
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        probe.send("synthetic apple")
        let old = try router.freezeQuickRecordingRelease()
        try await router.completeQuickRecordingRelease(old)
        probe.send("synthetic delayed final", type: .final)
        await assertEventually { finals.withLock { $0 } == 1 }
        XCTAssertEqual(finals.withLock { $0 }, 1)
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        probe.send("stale synthetic apple", type: .final, index: 0)
        try await router.completeQuickRecordingRelease(old)
        XCTAssertTrue(router.isTranscribing)
        let next = try router.freezeQuickRecordingRelease()
        XCTAssertFalse(next.hasRecognizedSpeech)
        try await router.completeQuickRecordingRelease(next)
        await assertEventually { finals.withLock { $0 } == 1 }
        XCTAssertEqual(finals.withLock { $0 }, 1)
    }

    func testQuickRouterRemainsOccupiedUntilDiscardCleanupCompletes() async throws {
        let gate = QuickRecordingEffectGate()
        let probe = QuickRecordingEffectProbe(cleanupGate: gate)
        let source = QuickRecordingTestProvider.apple.make(probe)
        let router = makeSelectableCoordinator(permissionCoordinator: source) { source }
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        let frozen = try router.freezeQuickRecordingRelease()
        let completing = Task { try await router.completeQuickRecordingRelease(frozen) }
        await gate.entered()
        XCTAssertThrowsError(try router.prepareQuickRecording())
        await gate.release()
        try await completing.value
        try router.prepareQuickRecording()
    }

    func testQuickRouterForwardsFrozenSourceDecisionAndSealsDiscardedOutput() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let probe = QuickRecordingEffectProbe(realtime: provider == .realtime)
            let source = provider.make(probe)
            let router = makeSelectableCoordinator(permissionCoordinator: source) { source }
            let finals = Mutex(0)
            let subscription = router.observeFinals({ _ in
                finals.withLock { $0 += 1 }
            })
            try router.prepareQuickRecording()
            try await router.start(language: .current)
            let frozen = try router.freezeQuickRecordingRelease()
            probe.send("late synthetic apple", type: .final)
            try await router.completeQuickRecordingRelease(frozen)
            probe.send("late synthetic final", type: .final)
            XCTAssertEqual(finals.withLock { $0 }, 0)
            XCTAssertEqual(probe.count("batch"), 0)
            XCTAssertEqual(probe.count("endApple"), 0)
            XCTAssertEqual(probe.count("stop"), 1)
            subscription.cancel()
        }
    }

    func testQuickReleaseDuringSelectionNeverStartsChosenSource() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.apple.make(probe)
        let gate = FakeSelectionGate()
        let router = makeSelectableCoordinator(permissionCoordinator: source) {
            await gate.wait(); return source
        }
        try router.prepareQuickRecording()
        let starting = Task { try await router.start(language: .current) }
        await gate.entered()
        let frozen = try router.freezeQuickRecordingRelease()
        let completing = Task { try await router.completeQuickRecordingRelease(frozen) }
        await gate.release()
        _ = await starting.result
        try await completing.value
        XCTAssertEqual(probe.count("start"), 0)
        XCTAssertEqual(probe.count("endApple"), 0)
        XCTAssertFalse(router.isTranscribing)
        try router.prepareQuickRecording()
    }

    func testQuickEligibleDecisionCanBeExplicitlyDiscardedThroughRouter() async throws {
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.apple.make(probe)
        let router = makeSelectableCoordinator(permissionCoordinator: source) { source }
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        probe.send("synthetic apple")
        let frozen = try router.freezeQuickRecordingRelease()
        XCTAssertTrue(frozen.hasRecognizedSpeech)
        try await router.completeQuickRecordingRelease(.init(sessionID: frozen.sessionID, hasRecognizedSpeech: false))
        XCTAssertEqual(probe.count("cancelApple"), 1)
        XCTAssertEqual(probe.count("endApple"), 0)
    }

    func testQuickUnsupportedSourceFailsWithoutStartingOrNormalStop() async throws {
        let source = FakeSelectableTranscriber()
        let router = makeSelectableCoordinator(permissionCoordinator: source) { source }
        try router.prepareQuickRecording()
        do { try await router.start(language: .current); XCTFail("Expected unsupported capability") }
        catch { XCTAssertTrue(error is QuickRecordingReleaseError) }
        XCTAssertEqual(source.startCount.withLock { $0 }, 0)
        XCTAssertEqual(source.stopCount.withLock { $0 }, 0)
        try router.prepareQuickRecording()
    }

    func testSupportedQuickStartupFailureCleansAndAllowsImmediateNextSession() async throws {
        for provider in QuickRecordingTestProvider.allCases {
            let failed = QuickRecordingEffectProbe(startFails: true)
            let failedSource = provider.make(failed)
            let selection = Mutex<any SpeechSessionSource>(failedSource)
            let router = makeSelectableCoordinator(permissionCoordinator: failedSource) {
                selection.withLock { $0 }
            }
            try router.prepareQuickRecording()
            do { try await router.start(language: .current); XCTFail("Expected startup failure") }
            catch { XCTAssertTrue(error is QuickRecordingReleaseError) }
            XCTAssertEqual(failed.count("stop"), 1)
            XCTAssertEqual(failed.count("cancelApple"), 1)
            XCTAssertEqual(failed.count("removeAudio"), 1)
            XCTAssertEqual(failed.count("endApple"), 0)
            XCTAssertEqual(failed.count("batch"), 0)
            let next = QuickRecordingEffectProbe()
            selection.withLock { $0 = provider.make(next) }
            try router.prepareQuickRecording()
            try await router.start(language: .current)
            failed.send("stale Apple", type: .final)
            let frozen = try router.freezeQuickRecordingRelease()
            XCTAssertFalse(frozen.hasRecognizedSpeech)
            try await router.completeQuickRecordingRelease(frozen)
            XCTAssertEqual(next.count("stop"), 1)
        }
    }

    func testPendingOldCompletionCannotDiscardNewEligibleSession() async throws {
        let gate = FakeSelectionGate()
        let cancelled = expectation(description: "old release is awaiting cancelled startup")
        let firstSelection = Mutex(true)
        let probe = QuickRecordingEffectProbe()
        let source = QuickRecordingTestProvider.batch.make(probe)
        let router = makeSelectableCoordinator(permissionCoordinator: source) {
            let first = firstSelection.withLock { first in defer { first = false }; return first }
            if first {
                await withTaskCancellationHandler { await gate.wait() } onCancel: { cancelled.fulfill() }
                throw QuickRecordingReleaseError.unsupported
            }
            return source
        }
        try router.prepareQuickRecording()
        let starting = Task { try await router.start(language: .current) }
        await gate.entered()
        let old = try router.freezeQuickRecordingRelease()
        XCTAssertFalse(old.hasRecognizedSpeech)
        let executor = PausedQuickReleaseExecutor()
        defer { executor.resume() }
        let completing = Task(executorPreference: executor) { try await router.completeQuickRecordingRelease(old) }
        await executor.runNext()
        await fulfillment(of: [cancelled], timeout: 1)
        await gate.release()
        if case .success = await starting.result { XCTFail("Old startup must fail") }

        // A 的完成仍排队；先让 B 启动、收到 Apple 文本并冻结资格。
        try router.prepareQuickRecording()
        try await router.start(language: .current)
        probe.send("synthetic eligible Apple")
        let next = try router.freezeQuickRecordingRelease()
        XCTAssertNotEqual(next.sessionID, old.sessionID)
        XCTAssertTrue(next.hasRecognizedSpeech)
        executor.resume()
        try await completing.value
        XCTAssertTrue(router.isTranscribing)
        XCTAssertTrue(source.isTranscribing)
        for effect in ["stop", "cancelApple", "cancelRealtime", "removeAudio", "endApple", "batch"] {
            XCTAssertEqual(probe.count(effect), 0, "Old completion affected new session: \(effect)")
        }
        XCTAssertEqual(try router.freezeQuickRecordingRelease(), next)
        try await router.completeQuickRecordingRelease(next)
        XCTAssertEqual(probe.count("endApple"), 1)
        XCTAssertEqual(probe.count("batch"), 1)
        XCTAssertEqual(probe.count("stop"), 1)
    }

    func testSystemSpeechFinalCanArriveAfterStopReturns() async throws {
        let fake = FakeSelectableTranscriber()
        let router = makeSelectableCoordinator(permissionCoordinator: fake) { fake }
        let seen = Mutex<[String]>([])
        let subscription = router.observeFinals({ value in
            seen.withLock { $0.append(value.text) }
        })
        defer { subscription.cancel() }
        try await router.start(language: .current)
        await router.stop()
        XCTAssertFalse(router.isTranscribing)
        fake.sendFinal("delayed system final")
        await assertEventually { seen.withLock { $0 } == ["delayed system final"] }
        XCTAssertEqual(seen.withLock { $0 }, ["delayed system final"])
    }

    func testSelectionChangesOnNextStartAndOldPublishersAreIsolated() async throws {
        let first = FakeSelectableTranscriber()
        let second = FakeSelectableTranscriber()
        let selection = Mutex<any SpeechSessionSource>(first)
        let router = makeSelectableCoordinator(permissionCoordinator: first) { selection.withLock { $0 } }
        let received = Mutex<[String]>([])
        let finals = router.observeFinals({ value in
            received.withLock { $0.append(value.text) }
        })
        defer { finals.cancel() }
        try await router.start(language: .current)
        selection.withLock { $0 = second }
        XCTAssertTrue(first.isTranscribing)
        XCTAssertFalse(second.isTranscribing)
        first.sendFinal("first")
        await assertEventually { received.withLock { $0 } == ["first"] }
        await router.stop()
        try await router.start(language: .current)
        first.sendFinal("stale")
        second.sendFinal("second")
        await assertEventually { received.withLock { $0 } == ["first", "second"] }
        XCTAssertEqual(received.withLock { $0 }, ["first", "second"])
        await router.stop()
        XCTAssertFalse(router.isTranscribing)
    }

    func testStopDuringFactoryWaitNeverStartsMicrophone() async throws {
        let fake = FakeSelectableTranscriber()
        let gate = FakeSelectionGate()
        let cancelled = expectation(description: "selection lookup cancelled")
        let router = makeSelectableCoordinator(permissionCoordinator: fake) {
            await withTaskCancellationHandler { await gate.wait() } onCancel: { cancelled.fulfill() }
            return fake
        }
        let starting = Task { try await router.start(language: .current) }
        await gate.entered()
        let stopping = Task { await router.stop() }
        await fulfillment(of: [cancelled], timeout: 1)
        await gate.release()
        _ = await starting.result
        await stopping.value
        XCTAssertFalse(fake.isTranscribing)
        XCTAssertEqual(fake.startCount.withLock { $0 }, 0)
        XCTAssertFalse(router.isTranscribing)
    }

    func testBackendFailureDoesNotTerminateSubsequentRecordings() async throws {
        let first = FakeSelectableTranscriber()
        let second = FakeSelectableTranscriber()
        let selection = Mutex<any SpeechSessionSource>(first)
        let router = makeSelectableCoordinator(permissionCoordinator: first) { selection.withLock { $0 } }
        let seen = Mutex<[String]>([])
        let subscriber = router.observePartials({ value in seen.withLock { $0.append(value.text) } })
        defer { subscriber.cancel() }
        try await router.start(language: .current)
        first.fail()
        await assertEventually { router.captureState == .error("语音识别失败，请重试。") }
        XCTAssertEqual(router.captureState, .error("语音识别失败，请重试。"))
        await router.stop()
        selection.withLock { $0 = second }
        try await router.start(language: .current)
        second.sendLive("next")
        await assertEventually { seen.withLock { $0 } == ["next"] }
        XCTAssertEqual(seen.withLock { $0 }, ["next"])
        await router.stop()
    }
}

private final class FakeSelectableTranscriber: SpeechSessionSource, SpeechSession {
    private let running = Mutex(false)
    let startCount = Mutex(0)
    let stopCount = Mutex(0)
    private let relay = SpeechSessionRelay()
    private let stream = Mutex<AsyncThrowingStream<TranscriptionEvent, Error>?>(nil)
    var isActive: Bool { running.withLock { $0 } }
    var isTranscribing: Bool { isActive }
    var providerKind: ASRProviderType { .custom }
    var supportedLanguages: [Locale] { [.current] }
    var hasMicrophonePermission: Bool { true }
    var hasSpeechPermission: Bool { true }
    func requestMicrophonePermission() async -> Bool { true }
    func requestSpeechPermission() async -> Bool { true }
    func captureStates() -> AsyncStream<AudioCaptureState> { AsyncStream { $0.yield(.idle) } }
    func audioLevels() -> AsyncStream<Float> { AsyncStream { $0.yield(0) } }
    func startSession(language: Locale) async throws -> any SpeechSession {
        let opened = relay.open().1
        stream.withLock { $0 = opened }
        startCount.withLock { $0 += 1 }
        running.withLock { $0 = true }
        return self
    }
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error> { stream.withLock { $0! } }
    func stop() async { stopCount.withLock { $0 += 1 }; running.withLock { $0 = false } }
    func cancel() async { await stop(); relay.finish() }
    func pause() async {}
    func resume() async {}
    func sendLive(_ text: String) { relay.send(.partial(.init(text: text, type: .partial, locale: .current))) }
    func sendFinal(_ text: String) { relay.send(.final(.init(text: text, type: .final, locale: .current))) }
    func fail() { relay.finish(throwing: RealtimeTranscriptionError.connectionFailed) }
}

private actor FakeSelectionGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            observers.forEach { $0.resume() }; observers.removeAll()
        }
    }
    func entered() async {
        if waiting != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { waiting?.resume(); waiting = nil }
}

/// 只控制旧 complete 的执行器；启动失败和新录音继续使用正常执行器。
private final class PausedQuickReleaseExecutor: TaskExecutor {
    private struct State {
        var jobs: [UnownedJob] = []
        var waiter: CheckedContinuation<UnownedJob, Never>?
        var resumed = false
    }
    private let state = Mutex(State())

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let action = state.withLock { state -> (Bool, CheckedContinuation<UnownedJob, Never>?) in
            if state.resumed { return (true, nil) }
            if let waiter = state.waiter { state.waiter = nil; return (false, waiter) }
            state.jobs.append(job)
            return (false, nil)
        }
        if action.0 { schedule(job) } else { action.1?.resume(returning: job) }
    }

    func runNext() async {
        let job = await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> UnownedJob? in
                if !state.jobs.isEmpty { return state.jobs.removeFirst() }
                state.waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
        job.runSynchronously(on: asUnownedTaskExecutor())
    }

    func resume() {
        let jobs = state.withLock { state in
            state.resumed = true
            defer { state.jobs.removeAll() }
            return state.jobs
        }
        jobs.forEach(schedule)
    }

    private func schedule(_ job: UnownedJob) {
        Task.detached { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }
}
