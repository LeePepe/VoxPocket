import Foundation
import Synchronization
import Testing
@testable import Preferences

struct ProductTelemetryPreferencesTests {
    @Test func consentDefaultsOffWithoutCreatingIdentity() async {
        let fixture = Fixture()
        let recorder = IdentityRecorder()
        let preferences = ProductTelemetryPreferences(
            store: fixture.store,
            identityGenerator: { recorder.record(UUID()) }
        )

        #expect(await preferences.isConsented == false)
        #expect(await preferences.installIdentityIfConsented() == nil)
        #expect(recorder.identities.isEmpty)
        #expect(fixture.persistedIdentity == nil)
    }

    @Test func productionInitializerCreatesAndPersistsOpaqueRandomIdentity() async {
        let fixture = Fixture()
        let preferences = ProductTelemetryPreferences(store: fixture.store)

        let identity = await preferences.setConsent(true)

        #expect(identity != nil)
        #expect(fixture.persistedIdentity == identity)
    }

    @Test func firstOptInPersistsOneIdentityAndEveryLaterOptInReusesIt() async {
        let fixture = Fixture()
        let recorder = IdentityRecorder()
        let generated = UUID()
        let preferences = ProductTelemetryPreferences(
            store: fixture.store,
            identityGenerator: { recorder.record(generated) }
        )

        let first = await preferences.setConsent(true)
        await preferences.setConsent(false)
        #expect(await preferences.installIdentityIfConsented() == nil)
        #expect(fixture.persistedIdentity == generated)
        let second = await preferences.setConsent(true)
        let relaunched = ProductTelemetryPreferences(
            store: fixture.store,
            identityGenerator: {
                Issue.record("A persisted installation identity must be reused")
                return UUID()
            }
        )

        #expect(first == generated)
        #expect(second == generated)
        #expect(await relaunched.installIdentityIfConsented() == generated)
        #expect(recorder.identities == [generated])
    }

    @Test func concurrentOptInCreatesOnlyOneInstallationIdentity() async {
        let fixture = Fixture()
        let recorder = IdentityRecorder()
        let preferences = ProductTelemetryPreferences(
            store: fixture.store,
            identityGenerator: { recorder.record(UUID()) }
        )

        async let first = preferences.setConsent(true)
        async let second = preferences.setConsent(true)
        let values = await [first, second]

        #expect(Set(values.compactMap { $0 }).count == 1)
        #expect(recorder.identities.count == 1)
    }

    @Test func genericPreferenceAPIHasNoIdentityKeyOrMutationSurface() async {
        let fixture = Fixture()
        let generated = UUID()
        let preferences = ProductTelemetryPreferences(
            store: fixture.store,
            identityGenerator: { generated }
        )

        #expect(
            !PreferencesKey.allCases
                .map(\.rawValue)
                .contains(Fixture.installIdentityKey)
        )
        #expect(await preferences.setConsent(true) == generated)

        for key in PreferencesKey.allCases {
            await fixture.store.setValue(UUID(), for: key)
            await fixture.store.removeValue(for: key)
        }

        #expect(fixture.persistedIdentity == generated)
        #expect(await preferences.setConsent(true) == generated)
    }
}

private final class Fixture {
    static let installIdentityKey = "telemetry.product.installIdentity"

    let store: UserDefaultsPreferencesStore
    private let suite: String

    var persistedIdentity: UUID? {
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        guard let data = defaults.data(forKey: Self.installIdentityKey) else { return nil }
        return try? JSONDecoder().decode(UUID.self, from: data)
    }

    init() {
        let suite = "ProductTelemetryPreferencesTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        self.suite = suite
        store = UserDefaultsPreferencesStore(defaults: defaults)
    }
}

private final class IdentityRecorder: Sendable {
    private let recordedIdentities = Mutex<[UUID]>([])

    var identities: [UUID] {
        recordedIdentities.withLock { $0 }
    }

    func record(_ identity: UUID) -> UUID {
        recordedIdentities.withLock { $0.append(identity) }
        return identity
    }
}
