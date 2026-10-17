import Foundation
import Testing
@testable import UseCases

@MainActor
struct ProductTelemetryActivationUseCaseTests {
    @Test func defaultOffAndIneligibleStartupNeverInstallIdentity() async {
        let recorder = ActivationRecorder(consent: false)
        let useCase = recorder.makeUseCase()

        await useCase.activateAtStartupIfEligible(true)
        #expect(!useCase.isReady)
        recorder.consent = true
        await useCase.activateAtStartupIfEligible(false)
        #expect(!useCase.isReady)

        #expect(recorder.operations == ["read"])
    }

    @Test func explicitTransitionsPersistOrderedBooleansAndTerminateEveryWaiter() async {
        let gate = AsyncGate()
        let recorder = ActivationRecorder(consent: false, persistGate: gate.suspendFirst)
        let useCase = recorder.makeUseCase()
        let enabling = useCase.beginConsentTransition(true, isEligible: true)
        await gate.waitUntilSuspended()
        let disabling = useCase.beginConsentTransition(false, isEligible: true)
        await gate.release()
        await enabling.value
        await disabling.value
        await useCase.waitForPendingTransition()

        #expect(recorder.writes == [true, false])
        #expect(!useCase.isReady)
        #expect(recorder.identities.isEmpty)
        #expect(recorder.operations == [
            "persist true",
            "deactivate",
            "persist false",
        ])
    }

    @Test func startupDefersBehindExplicitTransition() async {
        let gate = AsyncGate()
        let events = StartupDeferralEvents()
        let recorder = ActivationRecorder(consent: false, persistGate: gate.suspendFirst)
        let useCase = recorder.makeUseCase(
            pendingTransitionAwaiter: { capturedTransition in
                await events.record(.waiterEntered)
                await capturedTransition?.value
            }
        )

        let transition = useCase.beginConsentTransition(true, isEligible: true)
        await gate.waitUntilSuspended()
        let startup = Task {
            await useCase.activateAtStartupIfEligible(true)
            await events.record(.startupReturned)
        }
        let firstEvent = await events.first()
        if firstEvent != .waiterEntered {
            await gate.release()
            await transition.value
            await startup.value
        }
        #expect(firstEvent == .waiterEntered)
        await assertStartupIsDeferred(recorder: recorder, events: events)
        if firstEvent == .waiterEntered {
            await gate.release()
            await transition.value
            await startup.value
        }
        await assertStartupCompletedOnce(recorder: recorder, events: events, useCase: useCase)
    }

    private func assertStartupIsDeferred(
        recorder: ActivationRecorder,
        events: StartupDeferralEvents
    ) async {
        #expect(await events.waiterCount == 1)
        #expect(recorder.operations == ["persist true"])
        #expect(recorder.identities.isEmpty)
    }

    private func assertStartupCompletedOnce(
        recorder: ActivationRecorder,
        events: StartupDeferralEvents,
        useCase: DefaultProductTelemetryActivationUseCase
    ) async {
        #expect(await events.waiterCount == 1)
        #expect(recorder.writes == [true])
        #expect(recorder.operations == [
            "persist true",
            "read", "identity", "activate",
            "read", "identity", "activate",
        ])
        #expect(recorder.identities.count == 2)
        #expect(Set(recorder.identities).count == 1)
        #expect(useCase.isReady)
    }

    @Test func eligibilityIsCheckedBeforeConsentAndIdentity() async {
        let recorder = ActivationRecorder(consent: true)
        let useCase = recorder.makeUseCase()

        await useCase.activateAtStartupIfEligible(false)
        #expect(!useCase.isReady)

        #expect(recorder.operations.isEmpty)
        #expect(recorder.identities.isEmpty)
    }

    @Test func identityIsReusedAcrossDisableAndReenable() async {
        let recorder = ActivationRecorder(consent: false)
        let useCase = recorder.makeUseCase()

        await useCase.beginConsentTransition(true, isEligible: true).value
        await useCase.beginConsentTransition(false, isEligible: true).value
        await useCase.beginConsentTransition(true, isEligible: true).value

        #expect(recorder.identities.count == 2)
        #expect(Set(recorder.identities).count == 1)
        #expect(useCase.isReady)
    }

    #if DEBUG
    @Test func staleActivationCannotRestoreReadiness() async {
        let checkpoint = AsyncGate()
        let recorder = ActivationRecorder(consent: true)
        let useCase = recorder.makeUseCase {
            await checkpoint.suspendFirst()
        }

        let startup = Task { await useCase.activateAtStartupIfEligible(true) }
        await checkpoint.waitUntilSuspended()
        await useCase.beginConsentTransition(false, isEligible: true).value
        await checkpoint.release()

        await startup.value
        #expect(!useCase.isReady)
    }

    @Test func staleStartupCannotChangeFalseThenTrueWinnerSnapshot() async {
        let checkpoint = AsyncGate()
        let recorder = ActivationRecorder(consent: true)
        let useCase = recorder.makeUseCase {
            await checkpoint.suspendFirst()
        }

        let startup = Task { await useCase.activateAtStartupIfEligible(true) }
        await checkpoint.waitUntilSuspended()
        let disabling = useCase.beginConsentTransition(false, isEligible: true)
        await disabling.value
        let enabling = useCase.beginConsentTransition(true, isEligible: true)
        let pendingWaiter = Task { await useCase.waitForPendingTransition() }
        await enabling.value
        await pendingWaiter.value

        #expect(useCase.isReady)
        #expect(recorder.writes == [false, true])
        #expect(recorder.identities.count == 2)
        #expect(Set(recorder.identities).count == 1)
        #expect(recorder.operations == [
            "read", "identity", "activate",
            "deactivate", "persist false",
            "persist true", "read", "identity", "activate",
        ])
        let winningReadiness = useCase.isReady
        let winningConsent = recorder.consent
        let winningWrites = recorder.writes
        let winningIdentities = recorder.identities
        let winningOperations = recorder.operations

        await checkpoint.release()
        await startup.value
        await disabling.value
        await enabling.value
        await pendingWaiter.value

        #expect(useCase.isReady == winningReadiness)
        #expect(recorder.consent == winningConsent)
        #expect(recorder.writes == winningWrites)
        #expect(recorder.identities == winningIdentities)
        #expect(recorder.operations == winningOperations)
    }
    #endif

    @Test func failedActivationCanRetryWithoutCreatingAnotherPolicyWorker() async {
        let recorder = ActivationRecorder(consent: true, activationResults: [false, true])
        let useCase = recorder.makeUseCase()

        await useCase.activateAtStartupIfEligible(true)
        #expect(!useCase.isReady)
        await useCase.activateAtStartupIfEligible(true)

        #expect(recorder.identities.count == 2)
        #expect(Set(recorder.identities).count == 1)
        #expect(useCase.isReady)
    }

    @Test func readinessGatesRecordAndFlushAcrossActivationAndOptOut() async {
        let recorder = ActivationRecorder(consent: true)
        let useCase = recorder.makeUseCase()
        let telemetry = ReadinessGatedTelemetry(activation: useCase)

        telemetry.record()
        telemetry.flush()
        #expect(telemetry.operations.isEmpty)

        await useCase.activateAtStartupIfEligible(true)
        telemetry.record()
        telemetry.flush()
        #expect(telemetry.operations == ["record", "flush"])

        await useCase.beginConsentTransition(false, isEligible: true).value
        telemetry.record()
        telemetry.flush()
        #expect(telemetry.operations == ["record", "flush"])
    }
}

@MainActor
private final class ActivationRecorder {
    var consent: Bool
    var operations: [String] = []
    var writes: [Bool] = []
    var identities: [UUID] = []

    private let identity = UUID()
    private var activationResults: [Bool]
    private let persistGate: (@Sendable (Bool) async -> Void)?

    init(
        consent: Bool,
        activationResults: [Bool] = [true],
        persistGate: (@Sendable (Bool) async -> Void)? = nil
    ) {
        self.consent = consent
        self.activationResults = activationResults
        self.persistGate = persistGate
    }

    func makeDependencies() -> ProductTelemetryActivationDependencies {
        ProductTelemetryActivationDependencies(
            readConsent: { [self] in
                operations.append("read")
                return consent
            },
            persistConsent: { [self] value in
                operations.append("persist \(value)")
                await persistGate?(value)
                writes.append(value)
                consent = value
            },
            installIdentityIfConsented: { [self] in
                operations.append("identity")
                guard consent else { return nil }
                identities.append(identity)
                return identity
            },
            activate: { [self] _ in
                operations.append("activate")
                return activationResults.isEmpty ? true : activationResults.removeFirst()
            },
            deactivate: { [self] in
                operations.append("deactivate")
            }
        )
    }

    func makeUseCase() -> DefaultProductTelemetryActivationUseCase {
        DefaultProductTelemetryActivationUseCase(dependencies: makeDependencies())
    }

    #if DEBUG
    func makeUseCase(
        activationCheckpoint: @escaping DefaultProductTelemetryActivationUseCase.ActivationCheckpoint
    ) -> DefaultProductTelemetryActivationUseCase {
        DefaultProductTelemetryActivationUseCase(
            dependencies: makeDependencies(),
            activationCheckpoint: activationCheckpoint
        )
    }

    func makeUseCase(
        pendingTransitionAwaiter: @escaping DefaultProductTelemetryActivationUseCase.PendingTransitionAwaiter
    ) -> DefaultProductTelemetryActivationUseCase {
        DefaultProductTelemetryActivationUseCase(
            dependencies: makeDependencies(),
            activationCheckpoint: {},
            pendingTransitionAwaiter: pendingTransitionAwaiter
        )
    }
    #endif
}

@MainActor
private final class ReadinessGatedTelemetry {
    private let activation: any ProductTelemetryActivationUseCase
    private(set) var operations: [String] = []

    init(activation: any ProductTelemetryActivationUseCase) {
        self.activation = activation
    }

    func record() {
        guard activation.isReady else { return }
        operations.append("record")
    }

    func flush() {
        guard activation.isReady else { return }
        operations.append("flush")
    }
}

private actor AsyncGate {
    private var didSuspend = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspendFirst(_: Bool = true) async {
        guard !didSuspend else { return }
        didSuspend = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilSuspended() async {
        guard !didSuspend else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor StartupDeferralEvents {
    enum Event: Equatable {
        case waiterEntered
        case startupReturned
    }

    private var recorded: [Event] = []
    private var firstWaiter: CheckedContinuation<Event, Never>?

    var waiterCount: Int {
        recorded.count { $0 == .waiterEntered }
    }

    func record(_ event: Event) {
        recorded.append(event)
        firstWaiter?.resume(returning: recorded[0])
        firstWaiter = nil
    }

    func first() async -> Event {
        if let first = recorded.first {
            return first
        }
        return await withCheckedContinuation { firstWaiter = $0 }
    }
}
