import Foundation
import Preferences
import Testing
@testable import UIShared

@MainActor
struct ProductTelemetrySettingsViewModelTests {
    @Test func freshStoreLoadsDefaultOffWithoutMutation() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let model = ProductTelemetrySettingsViewModel(
            preferences: ProductTelemetryPreferences(store: fixture.store),
            onConsentChanged: { _ in }
        )

        await model.load()

        #expect(model.isLoaded)
        #expect(!model.isSendingUsageData)
        let stored: Bool? = await fixture.store.getValue(for: .productTelemetryConsent)
        #expect(stored == nil)
    }

    @Test func everyChoiceNotifiesButOnlyLatestRequestRenders() async {
        let fixture = Fixture()
        defer { fixture.remove() }
        let notifier = ConsentNotifierGate()
        let model = ProductTelemetrySettingsViewModel(
            preferences: ProductTelemetryPreferences(store: fixture.store),
            onConsentChanged: { await notifier.notify($0) }
        )

        let obsoleteEnable = Task { await model.setSendingUsageData(true) }
        await notifier.waitUntilEnableSuspended()
        await model.setSendingUsageData(false)
        notifier.releaseEnable()
        await obsoleteEnable.value

        #expect(notifier.changes == [true, false])
        #expect(!model.isSendingUsageData)
        #expect(fixture.persistedIdentity == nil)
        let stored: Bool? = await fixture.store.getValue(for: .productTelemetryConsent)
        #expect(stored == nil)
    }
}

@MainActor
private final class ConsentNotifierGate {
    private(set) var changes: [Bool] = []
    private var enableSuspended = false
    private var enableSuspensionWaiter: CheckedContinuation<Void, Never>?
    private var enableReleaseWaiter: CheckedContinuation<Void, Never>?
    private var enableReleased = false

    func notify(_ consent: Bool) async {
        changes.append(consent)
        guard consent else { return }
        enableSuspended = true
        enableSuspensionWaiter?.resume()
        enableSuspensionWaiter = nil
        guard !enableReleased else { return }
        await withCheckedContinuation { enableReleaseWaiter = $0 }
    }

    func waitUntilEnableSuspended() async {
        guard !enableSuspended else { return }
        await withCheckedContinuation { enableSuspensionWaiter = $0 }
    }

    func releaseEnable() {
        enableReleased = true
        enableReleaseWaiter?.resume()
        enableReleaseWaiter = nil
    }
}

private struct Fixture {
    private static let installIdentityKey = "telemetry.product.installIdentity"

    let suite = "ProductTelemetrySettingsViewModelTests.\(UUID())"
    let store: UserDefaultsPreferencesStore

    var persistedIdentity: Data? {
        UserDefaults(suiteName: suite)?.data(forKey: Self.installIdentityKey)
    }

    init() {
        store = UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func remove() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}
