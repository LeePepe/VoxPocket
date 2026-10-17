import Foundation
import LokiKit
@testable import Preferences
import Synchronization
import Testing
import UIShared
@testable import VoxPocket

@MainActor
struct BlobTelemetryConsentCompositionTests {
    @Test func markedUITestAppUsesProductionCompositionWithoutConstructingBlob() async {
        let suite = "BlobTelemetryConsentCompositionTests.UITest.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let identityProvisions = Mutex(0)
        let recorder = ExcludedHostBlobRecorder()
        let preferences = ProductTelemetryPreferences(
            store: UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suite)!),
            identityGenerator: {
                identityProvisions.withLock { $0 += 1 }
                return UUID()
            }
        )
        await preferences.persistConsent(true)
        let configuration = BlobTelemetryConfiguration.enabled(.init(
            endpoint: URL(string: "https://telemetry.example.invalid/container")!,
            sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
        ))
        let container = ServiceContainer(
            productTelemetryPreferences: preferences,
            processEnvironment: [ServiceContainer.uiTestHostEnvironmentKey: "1"],
            processArguments: ["--vox-ui-test-host"],
            productTelemetryConfiguration: { configuration },
            productTelemetryBootstrapFactory: { identity in
                recorder.requestBootstrap(identity: identity)
                return .testing(
                    configuration: configuration,
                    host: .test,
                    isConsented: true,
                    makeService: { recorder.makeService() }
                )
            }
        )

        #expect(await preferences.isConsented)
        #expect(identityProvisions.withLock { $0 } == 0)
        #expect(recorder.counts == .zero)

        await container.completeProductTelemetryStartup(startedAt: .now)

        #expect(await preferences.isConsented)
        #expect(identityProvisions.withLock { $0 } == 0)
        #expect(recorder.counts == .zero)
        #expect(
            UserDefaults(suiteName: suite)?
                .data(forKey: "telemetry.product.installIdentity") == nil
        )
    }

    @Test func absentOrInvalidUITestMarkerCannotExcludeOrdinaryLaunch() {
        #expect(ServiceContainer.classifyBlobTelemetryHost(
            environment: [:],
            arguments: []
        ) == .interactiveApplication)
        #expect(ServiceContainer.classifyBlobTelemetryHost(
            environment: [ServiceContainer.uiTestHostEnvironmentKey: "0"],
            arguments: ["--vox-ui-test-host"]
        ) == .interactiveApplication)
        #expect(ServiceContainer.classifyBlobTelemetryHost(
            environment: [ServiceContainer.uiTestHostEnvironmentKey: "1"],
            arguments: []
        ) == .interactiveApplication)
    }

    @Test(arguments: BlobTelemetryHostKind.allCases.filter { $0 != .interactiveApplication })
    func excludedHostsNeverRequestBootstrapEvenWhenConsented(_ host: BlobTelemetryHostKind) async {
        let suite = "BlobTelemetryConsentCompositionTests.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = ProductTelemetryPreferences(
            store: UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        )
        await preferences.persistConsent(true)
        let bootstrapCalls = Mutex(0)
        let container = ServiceContainer(
            productTelemetryPreferences: preferences,
            processEnvironment: host == .test
                ? [ServiceContainer.uiTestHostEnvironmentKey: "1"] : [:],
            processArguments: host == .test ? ["--vox-ui-test-host"] : [],
            productTelemetryConfiguration: { .enabled(.init(
                endpoint: URL(string: "https://telemetry.example.invalid/container")!,
                sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
            )) },
            productTelemetryBootstrapFactory: { _ in
                bootstrapCalls.withLock { $0 += 1 }
                return .testing(
                    configuration: .disabled,
                    host: host,
                    isConsented: true,
                    makeService: { NoopTelemetryService() }
                )
            },
            productTelemetryHostOverride: host
        )

        await container.completeProductTelemetryStartup(startedAt: .now)

        #expect(bootstrapCalls.withLock { $0 } == 0)
        #expect(
            UserDefaults(suiteName: suite)?
                .data(forKey: "telemetry.product.installIdentity") == nil
        )
    }

    @Test func explicitOptInWithDisabledOrInvalidConfigurationConstructsNoTelemetryWork() async {
        for configuration in [
            BlobTelemetryConfiguration(testingInfoDictionary: [:]),
            BlobTelemetryConfiguration(testingInfoDictionary: [
                "LokiKitBlobEndpoint": "",
                "LokiKitBlobSAS": ""
            ]),
            BlobTelemetryConfiguration(testingInfoDictionary: [
                "LokiKitBlobEndpoint": "$(TELEMETRY_BLOB_ENDPOINT)",
                "LokiKitBlobSAS": "$(TELEMETRY_BLOB_SAS)"
            ]),
            .invalid(.invalidEndpoint)
        ] {
            let suite = "BlobTelemetryConsentCompositionTests.\(UUID())"
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            let defaults = UserDefaults(suiteName: suite)!
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let preferences = ProductTelemetryPreferences(store: store)
            let bootstrapCalls = Mutex(0)
            let serviceConstructions = Mutex(0)
            let container = ServiceContainer(
                productTelemetryPreferences: preferences,
                processEnvironment: [:],
                processArguments: [],
                productTelemetryConfiguration: { configuration },
                productTelemetryBootstrapFactory: { _ in
                    bootstrapCalls.withLock { $0 += 1 }
                    return .testing(
                        configuration: configuration,
                        host: .interactiveApplication,
                        isConsented: true,
                        makeService: {
                            serviceConstructions.withLock { $0 += 1 }
                            return NoopTelemetryService()
                        }
                    )
                }
            )
            let model = ProductTelemetrySettingsViewModel(preferences: preferences)

            await model.setSendingUsageData(true)
            await container.waitForPendingProductTelemetryConsentChange()

            #expect(model.isSendingUsageData)
            #expect(await preferences.isConsented)
            #expect(bootstrapCalls.withLock { $0 } == 0)
            #expect(serviceConstructions.withLock { $0 } == 0)
            #expect(defaults.data(forKey: "telemetry.product.installIdentity") == nil)
        }
    }
}

private final class ExcludedHostBlobRecorder: Sendable {
    struct Counts: Equatable, Sendable {
        var identityRequests = 0
        var bootstrapRequests = 0
        var serviceConstructions = 0
        var admissions = 0
        var storedEvents = 0
        var uploads = 0

        static let zero = Counts()
    }

    private let state = Mutex(Counts())

    var counts: Counts { state.withLock { $0 } }

    func requestBootstrap(identity: UUID) {
        _ = identity
        state.withLock {
            $0.identityRequests += 1
            $0.bootstrapRequests += 1
        }
    }

    func makeService() -> any TelemetryService {
        state.withLock { $0.serviceConstructions += 1 }
        return ExcludedHostBlobService(recorder: self)
    }

    func admitStore() {
        state.withLock {
            $0.admissions += 1
            $0.storedEvents += 1
        }
    }

    func admitUpload() {
        state.withLock { $0.uploads += 1 }
    }
}

private final class ExcludedHostBlobService: TelemetryService, Sendable {
    private let recorder: ExcludedHostBlobRecorder
    private let enabled = Mutex(true)

    init(recorder: ExcludedHostBlobRecorder) {
        self.recorder = recorder
    }

    var isEnabled: Bool {
        get { enabled.withLock { $0 } }
        set { enabled.withLock { $0 = newValue } }
    }

    func track(_ event: TelemetryEvent) {
        _ = event
        recorder.admitStore()
    }

    func track(name: String, properties: [String: String]) {
        _ = name
        _ = properties
        recorder.admitStore()
    }

    func flush() async {
        recorder.admitUpload()
    }

    func resetIdentifier() {}
}
