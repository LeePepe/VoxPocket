import Foundation
import LokiKit
import Synchronization
import Testing
@testable import VoxPocket

struct BlobTelemetryConsentTests {
    @Test(arguments: BlobTelemetryHostKind.allCases.filter { $0 != .interactiveApplication })
    func excludedHostsNeverConstructBlob(_ host: BlobTelemetryHostKind) async {
        let recorder = BlobLifecycleRecorder()
        let coordinator = makeCoordinator()
        let outcome = await coordinator.bootstrapBlob(.fixture(host: host, recorder: recorder))

        #expect(outcome == .ineligibleHost)
        #expect(recorder.constructionCount == 0)
        #expect(recorder.identityRequestCount == 0)
    }

    @Test func consentOffAndMissingConfigurationCreateNoBlobStateEvenWithRetainedIdentity() async {
        let recorder = BlobLifecycleRecorder()
        let coordinator = makeCoordinator()

        let off = await coordinator.bootstrapBlob(.fixture(isConsented: false, recorder: recorder))
        let missing = await coordinator.bootstrapBlob(.fixture(
            configuration: .disabled,
            retainedIdentity: UUID(),
            recorder: recorder
        ))

        #expect(off == .consentRequired)
        #expect(missing == .configurationDisabled)
        #expect(recorder.constructionCount == 0)
        #expect(recorder.identityRequestCount == 0)
        #expect(recorder.operations.isEmpty)
    }

    @Test func invalidConfigurationReportsOnlyFixedFailureWithoutConstruction() async {
        let recorder = BlobLifecycleRecorder()
        let coordinator = makeCoordinator()
        let outcome = await coordinator.bootstrapBlob(.fixture(
            configuration: .invalid(.invalidSAS),
            recorder: recorder
        ))

        #expect(outcome == .invalidConfiguration(.invalidSAS))
        #expect(outcome.diagnostic == "blob_configuration_invalid_sas")
        #expect(recorder.constructionCount == 0)
        #expect(recorder.identityRequestCount == 0)
    }

    @Test func enableTrackFlushDisableAndReenableUseOneSerializedCoordinatorGeneration() async throws {
        let recorder = BlobLifecycleRecorder()
        let coordinator = makeCoordinator()
        let identity = UUID()
        let request = BlobTelemetryBootstrap.fixture(retainedIdentity: identity, recorder: recorder)

        #expect(await coordinator.bootstrapBlob(request) == .ready)
        coordinator.trackBlob(.userAction(.quickRecordStarted))
        await coordinator.flushBlob()
        await coordinator.disableBlob()
        coordinator.trackBlob(.userAction(.quickRecordStopped))
        await coordinator.flushBlob()
        #expect(await coordinator.bootstrapBlob(request) == .ready)
        coordinator.trackBlob(try .performance(.appLaunch, durationMilliseconds: 10))
        await coordinator.flushBlob()

        #expect(recorder.constructionCount == 1)
        #expect(recorder.identityRequestCount == 1)
        #expect(recorder.identities == [identity])
        #expect(recorder.operations == [
            "construct", "track product.user_action", "flush", "disable",
            "enable", "track product.performance", "flush"
        ])
        #expect(recorder.maximumConcurrency == 1)
        #expect(recorder.mainThreadCalls == 0)
        #expect(recorder.resetCount == 0)
    }

    @Test func adjacentBlobFlushesJoinOneUnderlyingFlush() async {
        let gate = BlobFlushGate()
        let admissions = BlobAdmissionGate()
        let recorder = BlobLifecycleRecorder(flushGate: gate)
        let coordinator = TelemetryLifecycleCoordinator(
            isEnabled: false,
            flushAdmissionObserver: { admissions.record() }
        ) { NoopTelemetryService() }
        #expect(await coordinator.bootstrapBlob(.fixture(recorder: recorder)) == .ready)
        coordinator.trackBlob(.userAction(.quickRecordStarted))

        let first = Task { await coordinator.flushBlob() }
        await admissions.wait(for: 1)
        await gate.waitUntilEntered()
        let joined = Task { await coordinator.flushBlob() }
        await admissions.wait(for: 2)
        await gate.open()
        await first.value
        await joined.value

        #expect(recorder.operations.filter { $0 == "flush" }.count == 1)
    }

    @Test func interveningBlobAdmissionRequiresFollowUpFlush() async {
        let gate = BlobFlushGate()
        let admissions = BlobAdmissionGate()
        let recorder = BlobLifecycleRecorder(flushGate: gate)
        let coordinator = TelemetryLifecycleCoordinator(
            isEnabled: false,
            flushAdmissionObserver: { admissions.record() }
        ) { NoopTelemetryService() }
        #expect(await coordinator.bootstrapBlob(.fixture(recorder: recorder)) == .ready)
        coordinator.trackBlob(.userAction(.quickRecordStarted))

        let first = Task { await coordinator.flushBlob() }
        await admissions.wait(for: 1)
        await gate.waitUntilEntered()
        coordinator.trackBlob(.userAction(.quickRecordStopped))
        let followUp = Task { await coordinator.flushBlob() }
        await admissions.wait(for: 2)
        await gate.open()
        await first.value
        await followUp.value

        #expect(recorder.operations == [
            "construct", "track product.user_action", "flush",
            "track product.user_action", "flush"
        ])
    }

    private func makeCoordinator() -> TelemetryLifecycleCoordinator {
        TelemetryLifecycleCoordinator(isEnabled: false) { NoopTelemetryService() }
    }
}

private extension BlobTelemetryBootstrap {
    static func fixture(
        configuration: BlobTelemetryConfiguration = .enabled(.init(
            endpoint: URL(string: "https://telemetry.example.invalid/container")!,
            sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
        )),
        host: BlobTelemetryHostKind = .interactiveApplication,
        isConsented: Bool = true,
        retainedIdentity: UUID = UUID(),
        recorder: BlobLifecycleRecorder
    ) -> Self {
        Self.testing(
            configuration: configuration,
            host: host,
            isConsented: isConsented,
            makeService: {
                recorder.construct(identityProvider: {
                    recorder.requestIdentity(retainedIdentity)
                })
            }
        )
    }
}

private final class BlobLifecycleRecorder: Sendable {
    private struct State: Sendable {
        var constructionCount = 0
        var identityRequestCount = 0
        var identities: [UUID] = []
        var operations: [String] = []
        var concurrency = 0
        var maximumConcurrency = 0
        var mainThreadCalls = 0
        var resetCount = 0
    }
    private let state = Mutex(State())
    private let flushGate: BlobFlushGate?

    init(flushGate: BlobFlushGate? = nil) {
        self.flushGate = flushGate
    }

    var constructionCount: Int { state.withLock { $0.constructionCount } }
    var identityRequestCount: Int { state.withLock { $0.identityRequestCount } }
    var identities: [UUID] { state.withLock { $0.identities } }
    var operations: [String] { state.withLock { $0.operations } }
    var maximumConcurrency: Int { state.withLock { $0.maximumConcurrency } }
    var mainThreadCalls: Int { state.withLock { $0.mainThreadCalls } }
    var resetCount: Int { state.withLock { $0.resetCount } }

    func construct(identityProvider: @escaping @Sendable () throws -> UUID) -> any TelemetryService {
        begin("construct")
        state.withLock { $0.constructionCount += 1 }
        let identity = try! identityProvider()
        state.withLock { $0.identities.append(identity) }
        end()
        return RecordingBlobService(recorder: self, flushGate: flushGate)
    }

    func requestIdentity(_ identity: UUID) -> UUID {
        state.withLock { $0.identityRequestCount += 1 }
        return identity
    }

    func begin(_ operation: String) {
        state.withLock {
            $0.operations.append(operation)
            $0.concurrency += 1
            $0.maximumConcurrency = max($0.maximumConcurrency, $0.concurrency)
            if Thread.isMainThread { $0.mainThreadCalls += 1 }
        }
    }

    func end() { state.withLock { $0.concurrency -= 1 } }
    func reset() { state.withLock { $0.resetCount += 1 } }
}

private final class RecordingBlobService: TelemetryService, Sendable {
    private let recorder: BlobLifecycleRecorder
    private let enabled = Mutex(true)
    private let flushGate: BlobFlushGate?

    init(recorder: BlobLifecycleRecorder, flushGate: BlobFlushGate?) {
        self.recorder = recorder
        self.flushGate = flushGate
    }

    var isEnabled: Bool {
        get { enabled.withLock { $0 } }
        set {
            enabled.withLock { $0 = newValue }
            recorder.begin(newValue ? "enable" : "disable")
            recorder.end()
        }
    }

    func track(_ event: TelemetryEvent) {
        guard isEnabled else { return }
        recorder.begin("track \(event.name)")
        recorder.end()
    }

    func track(name: String, properties: [String: String]) {
        track(TelemetryEvent(name: name, properties: properties))
    }

    func flush() async {
        guard isEnabled else { return }
        recorder.begin("flush")
        if let flushGate {
            await flushGate.enter()
        }
        recorder.end()
    }

    func resetIdentifier() { recorder.reset() }
}

private actor BlobFlushGate {
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

private final class BlobAdmissionGate: Sendable {
    private struct State: Sendable {
        var count = 0
        var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    }
    private let state = Mutex(State())

    func record() {
        let ready = state.withLock { state in
            state.count += 1
            let ready = state.waiters.filter { $0.0 <= state.count }
            state.waiters.removeAll { $0.0 <= state.count }
            return ready.map(\.1)
        }
        ready.forEach { $0.resume() }
    }

    func wait(for target: Int) async {
        await withCheckedContinuation { continuation in
            let reached = state.withLock { state -> Bool in
                guard state.count < target else { return true }
                state.waiters.append((target, continuation))
                return false
            }
            if reached { continuation.resume() }
        }
    }
}
