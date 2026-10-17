import Combine
import Foundation
import Preferences
import Testing
@testable import UIShared

@MainActor
struct ProductTelemetrySettingsViewModelTests {
    @Test func freshStoreLoadsDefaultOffWithoutMutation() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let model = fixture.makeModel()

        await model.load()

        #expect(model.isLoaded)
        #expect(!model.isSendingUsageData)
        let stored: Bool? = await fixture.store.getValue(for: .productTelemetryConsent)
        #expect(stored == nil)
    }

    @Test(arguments: [true, false])
    func sameStorePeersConvergeOnlyAfterCommittedChoice(_ choice: Bool) async {
        let fixture = Fixture()
        defer { fixture.remove() }
        await fixture.preferences.persistConsent(!choice)
        let gate = ConsentTransitionGate(suspending: choice)
        let origin = fixture.makeModel(
            onConsentChanged: { await gate.persist($0, to: fixture.preferences) }
        )
        let peerCallbacks = CallbackRecorder()
        let peer = fixture.makeModel(onConsentChanged: { peerCallbacks.record($0) })
        await origin.load()
        await peer.load()

        let peerConverged = waitForValue(choice, from: peer)
        let transition = Task { await origin.setSendingUsageData(choice) }
        await gate.waitUntilSuspended()
        #expect(origin.isSendingUsageData == !choice)
        #expect(peer.isSendingUsageData == !choice)
        gate.release()
        await transition.value
        await peerConverged.value

        #expect(origin.isSendingUsageData == choice)
        #expect(peer.isSendingUsageData == choice)
        #expect(gate.changes == [choice])
        #expect(peerCallbacks.values.isEmpty)
    }

    @Test func rapidChoiceRejectsObsoleteCommittedReread() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let gate = ConsentTransitionGate(
            suspending: true,
            suspendsBeforePersistence: false
        )
        let model = fixture.makeModel(
            onConsentChanged: { await gate.persist($0, to: fixture.preferences) }
        )
        await model.load()

        let obsoleteEnable = Task { await model.setSendingUsageData(true) }
        await gate.waitUntilSuspended()
        await model.setSendingUsageData(false)
        gate.release()
        await obsoleteEnable.value

        #expect(gate.changes == [true, false])
        #expect(!model.isSendingUsageData)
        #expect(await fixture.preferences.isConsented == false)
        #expect(fixture.persistedIdentity == nil)
    }

    @Test func everyChoiceNotifiesButViewModelDoesNotWriteStore() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let gate = ConsentTransitionGate(suspending: true, persists: false)
        let model = fixture.makeModel(
            onConsentChanged: { await gate.persist($0, to: fixture.preferences) }
        )

        let obsoleteEnable = Task { await model.setSendingUsageData(true) }
        await gate.waitUntilSuspended()
        await model.setSendingUsageData(false)
        gate.release()
        await obsoleteEnable.value

        #expect(gate.changes == [true, false])
        #expect(!model.isSendingUsageData)
        #expect(fixture.persistedIdentity == nil)
        let stored: Bool? = await fixture.store.getValue(for: .productTelemetryConsent)
        #expect(stored == nil)
    }

    @Test(arguments: [false, true])
    func inFlightChoiceSurvivesExternalPulse(differentStore: Bool) async {
        let originFixture = Fixture()
        let peerFixture = differentStore ? Fixture() : originFixture
        defer {
            originFixture.remove()
            if differentStore { peerFixture.remove() }
        }
        let gate = ConsentTransitionGate(suspending: true)
        let originReads = ReadCompletionProbe()
        let peerReads = ReadCompletionProbe()
        let origin = originFixture.makeModel(
            readConsent: {
                let value = await originFixture.preferences.isConsented
                originReads.record()
                return value
            },
            onConsentChanged: { await gate.persist($0, to: originFixture.preferences) }
        )
        let peerCallbacks = CallbackRecorder()
        let peer = peerFixture.makeModel(
            center: originFixture.center,
            readConsent: {
                let value = await peerFixture.preferences.isConsented
                peerReads.record()
                return value
            },
            onConsentChanged: { peerCallbacks.record($0) }
        )
        await origin.load()
        await peer.load()

        let transition = Task { await origin.setSendingUsageData(true) }
        await gate.waitUntilSuspended()
        await postPulseAndWaitForRefresh(
            center: originFixture.center,
            originReads: originReads,
            peerReads: peerReads
        )
        #expect(!origin.isSendingUsageData)
        #expect(!peer.isSendingUsageData)

        let peerConverged = waitForValue(!differentStore, from: peer)
        gate.release()
        await transition.value
        await peerConverged.value
        #expect(origin.isSendingUsageData)
        #expect(peer.isSendingUsageData == !differentStore)
        #expect(peerCallbacks.values.isEmpty)
    }

    private func postPulseAndWaitForRefresh(
        center: NotificationCenter,
        originReads: ReadCompletionProbe,
        peerReads: ReadCompletionProbe
    ) async {
        let originRefreshed = originReads.waitForCount(2)
        let peerRefreshed = peerReads.waitForCount(2)
        center.post(name: ProductTelemetrySettingsViewModel.consentDidChange, object: nil)
        await originRefreshed.value
        await peerRefreshed.value
    }

    @Test func staleLoadCannotOverwriteLatestChoice() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let reads = ConsentReadGate(values: [false, true, true], suspendedCalls: [1])
        let model = fixture.makeModel(
            readConsent: { await reads.read() },
            onConsentChanged: { _ in }
        )

        let staleLoad = Task { await model.load() }
        await reads.waitUntilSuspended(call: 1)
        await model.setSendingUsageData(true)
        await reads.release(call: 1)
        await staleLoad.value
        #expect(model.isSendingUsageData)
    }

    @Test func stalePeerRefreshCannotOverwriteLatestChoice() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let reads = ConsentReadGate(values: [false, false, true, true], suspendedCalls: [2])
        let model = fixture.makeModel(
            readConsent: { await reads.read() },
            onConsentChanged: { _ in }
        )
        await model.load()

        fixture.center.post(
            name: ProductTelemetrySettingsViewModel.consentDidChange,
            object: nil
        )
        await reads.waitUntilSuspended(call: 2)
        await model.setSendingUsageData(true)
        await reads.release(call: 2)
        await reads.waitUntilCompleted(call: 2)
        #expect(model.isSendingUsageData)
    }

    @Test func completionPulseRereadsEachModelsOwnStore() async {
        let originFixture = Fixture()
        let peerFixture = Fixture()
        defer {
            originFixture.remove()
            peerFixture.remove()
        }
        await peerFixture.preferences.persistConsent(false)
        let peerReads = ReadCompletionProbe()
        let origin = originFixture.makeModel(
            onConsentChanged: { await originFixture.preferences.persistConsent($0) }
        )
        let peer = peerFixture.makeModel(
            center: originFixture.center,
            readConsent: {
                let value = await peerFixture.preferences.isConsented
                peerReads.record()
                return value
            },
            onConsentChanged: { _ in }
        )
        await origin.load()
        await peer.load()

        let peerRefreshed = peerReads.waitForCount(2)
        await origin.setSendingUsageData(true)
        await peerRefreshed.value

        #expect(origin.isSendingUsageData)
        #expect(!peer.isSendingUsageData)
        #expect(await originFixture.preferences.isConsented)
        #expect(await peerFixture.preferences.isConsented == false)
    }

    private func waitForValue(
        _ expected: Bool,
        from model: ProductTelemetrySettingsViewModel
    ) -> Task<Void, Never> {
        Task { @MainActor in
            for await value in model.$isSendingUsageData.values where value == expected {
                return
            }
        }
    }
}

@MainActor
private final class ConsentTransitionGate {
    private(set) var changes: [Bool] = []
    private let suspendedChoice: Bool
    private let persists: Bool
    private let suspendsBeforePersistence: Bool
    private var suspended = false
    private var suspensionWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    init(
        suspending choice: Bool,
        persists: Bool = true,
        suspendsBeforePersistence: Bool = true
    ) {
        suspendedChoice = choice
        self.persists = persists
        self.suspendsBeforePersistence = suspendsBeforePersistence
    }

    func persist(_ consent: Bool, to preferences: ProductTelemetryPreferences) async {
        changes.append(consent)
        if consent == suspendedChoice, suspendsBeforePersistence {
            await suspend()
        }
        if persists {
            await preferences.persistConsent(consent)
        }
        if consent == suspendedChoice, !suspendsBeforePersistence {
            await suspend()
        }
    }

    private func suspend() async {
        suspended = true
        suspensionWaiter?.resume()
        suspensionWaiter = nil
        if !released {
            await withCheckedContinuation { releaseWaiter = $0 }
        }
    }

    func waitUntilSuspended() async {
        guard !suspended else { return }
        await withCheckedContinuation { suspensionWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private final class CallbackRecorder {
    private(set) var values: [Bool] = []
    func record(_ value: Bool) { values.append(value) }
}

private actor ConsentReadGate {
    private let values: [Bool]
    private let suspendedCalls: Set<Int>
    private var callCount = 0
    private var suspendedWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releaseWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var completedCalls: Set<Int> = []
    private var completionWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    init(values: [Bool], suspendedCalls: Set<Int>) {
        self.values = values
        self.suspendedCalls = suspendedCalls
    }

    func read() async -> Bool {
        callCount += 1
        let call = callCount
        suspendedWaiters.removeValue(forKey: call)?.resume()
        if suspendedCalls.contains(call) {
            await withCheckedContinuation { releaseWaiters[call] = $0 }
        }
        completedCalls.insert(call)
        completionWaiters.removeValue(forKey: call)?.resume()
        return values[call - 1]
    }

    func waitUntilSuspended(call: Int) async {
        guard callCount < call else { return }
        await withCheckedContinuation { suspendedWaiters[call] = $0 }
    }

    func release(call: Int) {
        releaseWaiters.removeValue(forKey: call)?.resume()
    }

    func waitUntilCompleted(call: Int) async {
        guard !completedCalls.contains(call) else { return }
        await withCheckedContinuation { completionWaiters[call] = $0 }
    }
}

@MainActor
private final class ReadCompletionProbe {
    private var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record() {
        count += 1
        let ready = waiters.filter { count >= $0.0 }
        waiters.removeAll { count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func waitForCount(_ target: Int) -> Task<Void, Never> {
        Task { @MainActor in
            guard count < target else { return }
            await withCheckedContinuation { waiters.append((target, $0)) }
        }
    }
}

@MainActor
private final class Fixture {
    private static let installIdentityKey = "telemetry.product.installIdentity"

    let suite = "ProductTelemetrySettingsViewModelTests.\(UUID())"
    let store: UserDefaultsPreferencesStore
    let preferences: ProductTelemetryPreferences
    let center = NotificationCenter()

    var persistedIdentity: Data? {
        UserDefaults(suiteName: suite)?.data(forKey: Self.installIdentityKey)
    }

    init() {
        store = UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        preferences = ProductTelemetryPreferences(store: store)
    }

    func makeModel(
        center: NotificationCenter? = nil,
        readConsent: (@MainActor @Sendable () async -> Bool)? = nil,
        onConsentChanged: (@MainActor @Sendable (Bool) async -> Void)? = nil
    ) -> ProductTelemetrySettingsViewModel {
        ProductTelemetrySettingsViewModel(
            preferences: preferences,
            notificationCenter: center ?? self.center,
            readConsent: readConsent ?? { [preferences] in await preferences.isConsented },
            onConsentChanged: onConsentChanged ?? { [preferences] in
                await preferences.persistConsent($0)
            }
        )
    }

    func remove() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}
