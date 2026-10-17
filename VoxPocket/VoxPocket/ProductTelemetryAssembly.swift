import Foundation
import LokiKit
import Preferences
import UIShared
import UseCases

typealias ProductTelemetryConfigurationProvider =
    @MainActor @Sendable () -> BlobTelemetryConfiguration
typealias ProductTelemetryBootstrapFactory =
    @MainActor @Sendable (UUID) -> BlobTelemetryBootstrap

@MainActor
struct ProductTelemetryAssembly {
    let preferences: ProductTelemetryPreferences
    let instrumentation: ProductTelemetryInstrumentation

    static func make(
        preferences: ProductTelemetryPreferences,
        environment: [String: String],
        arguments: [String],
        configuration: @escaping ProductTelemetryConfigurationProvider,
        bootstrapFactory: ProductTelemetryBootstrapFactory?,
        notificationCenter: NotificationCenter,
        hostOverride: BlobTelemetryHostKind?,
        coordinator: TelemetryLifecycleCoordinator
    ) -> Self {
        let host = hostOverride ?? ServiceContainer.classifyBlobTelemetryHost(
            environment: environment,
            arguments: arguments
        )
        let makeBootstrap = bootstrapFactory ?? defaultBootstrapFactory(host: host)
        let eligibility = eligibilityDecision(host: host, configuration: configuration)
        let activation = DefaultProductTelemetryActivationUseCase(
            dependencies: activationDependencies(
                preferences: preferences,
                coordinator: coordinator,
                makeBootstrap: makeBootstrap
            )
        )
        return Self(
            preferences: preferences,
            instrumentation: ProductTelemetryInstrumentation(
                activationUseCase: activation,
                isEligible: eligibility,
                track: { coordinator.trackBlob($0) },
                requestFlush: { coordinator.requestBlobFlush() },
                notificationCenter: notificationCenter
            )
        )
    }

    private static func defaultBootstrapFactory(
        host: BlobTelemetryHostKind
    ) -> ProductTelemetryBootstrapFactory {
        { identity in
            BlobTelemetryBootstrap.production(
                host: host,
                isConsented: true,
                storeDirectory: ServiceContainer.blobTelemetryStoreDirectory,
                identityProvider: { identity }
            )
        }
    }

    private static func eligibilityDecision(
        host: BlobTelemetryHostKind,
        configuration: @escaping ProductTelemetryConfigurationProvider
    ) -> ProductTelemetryInstrumentation.EligibilityDecision {
        {
            guard host.isEligibleForBlobTelemetry else { return false }
            guard case .enabled = configuration() else { return false }
            return true
        }
    }

    private static func activationDependencies(
        preferences: ProductTelemetryPreferences,
        coordinator: TelemetryLifecycleCoordinator,
        makeBootstrap: @escaping ProductTelemetryBootstrapFactory
    ) -> ProductTelemetryActivationDependencies {
        ProductTelemetryActivationDependencies(
            readConsent: { await preferences.isConsented },
            persistConsent: { await preferences.persistConsent($0) },
            installIdentityIfConsented: {
                await preferences.installIdentityIfConsented()
            },
            activate: { identity in
                await coordinator.bootstrapBlob(makeBootstrap(identity)) == .ready
            },
            deactivate: { await coordinator.disableBlob() }
        )
    }
}

@MainActor
final class ProductTelemetryInstrumentation {
    typealias EligibilityDecision = @MainActor @Sendable () -> Bool
    typealias Track = @MainActor @Sendable (BlobProductTelemetryEvent) -> Void
    typealias FlushRequest = @MainActor @Sendable () -> Task<Void, Never>

    private let activationUseCase: any ProductTelemetryActivationUseCase
    private let isEligible: EligibilityDecision
    private let track: Track
    private let requestFlush: FlushRequest
    private var observers: [NSObjectProtocol] = []
    private var pendingStartupCompletion: Task<Void, Never>?
    private var pendingSessionCompletion: Task<Void, Never>?

    init(
        activationUseCase: any ProductTelemetryActivationUseCase,
        isEligible: @escaping EligibilityDecision,
        track: @escaping Track,
        requestFlush: @escaping FlushRequest,
        notificationCenter: NotificationCenter = .default
    ) {
        self.activationUseCase = activationUseCase
        self.isEligible = isEligible
        self.track = track
        self.requestFlush = requestFlush
        observeConsentChanges(in: notificationCenter)
        observeActions(in: notificationCenter)
    }

    private func observeConsentChanges(in center: NotificationCenter) {
        observers.append(center.addObserver(
            forName: ProductTelemetrySettingsViewModel.consentDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let consent = notification.userInfo?["isConsented"] as? Bool else { return }
            MainActor.assumeIsolated {
                self?.beginConsentTransition(
                    consent,
                    completion: notification.userInfo?["transitionCompletion"]
                        as? AsyncStream<Void>.Continuation
                )
            }
        })
    }

    private func beginConsentTransition(
        _ consent: Bool,
        completion: AsyncStream<Void>.Continuation?
    ) {
        let transition = activationUseCase.beginConsentTransition(
            consent,
            isEligible: isEligible()
        )
        Task {
            await transition.value
            completion?.finish()
        }
    }

    private func observeActions(in center: NotificationCenter) {
        observe(ProductTelemetrySettingsViewModel.settingsDidOpen, action: .settingsOpened, in: center)
        observe(ProductTelemetryNotificationBoundary.fullPanelOpened, action: .fullPanelOpened, in: center)
        observe(ProductTelemetryNotificationBoundary.quickRecordStarted, action: .quickRecordStarted, in: center)
        observe(ProductTelemetryNotificationBoundary.quickRecordStopped, action: .quickRecordStopped, in: center)
    }

    private func observe(
        _ name: Notification.Name,
        action: BlobProductAction,
        in center: NotificationCenter
    ) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.record(action) }
        })
    }

    func waitForPendingConsentChange() async {
        await activationUseCase.waitForPendingTransition()
    }

    func completeStartup(startedAt: ContinuousClock.Instant) async {
        await activationUseCase.activateAtStartupIfEligible(isEligible())
        guard activationUseCase.isReady else { return }
        let duration = startedAt.duration(to: .now).components
        let milliseconds = min(
            3_600_000,
            max(0, Double(duration.seconds) * 1_000
                + Double(duration.attoseconds) / 1_000_000_000_000_000)
        )
        guard let event = try? BlobProductTelemetryEvent.performance(
            .appLaunch,
            durationMilliseconds: milliseconds
        ) else { return }
        track(event)
        pendingStartupCompletion = requestFlush()
    }

    func waitForPendingStartupCompletion() async {
        await pendingStartupCompletion?.value
    }

    func record(_ action: BlobProductAction) {
        guard activationUseCase.isReady else { return }
        track(.userAction(action))
    }

    func recordingDidComplete() async {
        await flush()
    }

    func sessionDidComplete() async {
        pendingSessionCompletion = flushRequest()
    }

    func waitForPendingSessionCompletion() async {
        await pendingSessionCompletion?.value
    }

    func applicationWillResignActive() async {
        await flush()
    }

    private func flush() async {
        await flushRequest()?.value
    }

    private func flushRequest() -> Task<Void, Never>? {
        guard activationUseCase.isReady else { return nil }
        return requestFlush()
    }
}

enum ProductTelemetryNotificationBoundary {
    static let fullPanelOpened = Notification.Name("vox.productTelemetry.fullPanelOpened")
    static let quickRecordStarted = Notification.Name("vox.productTelemetry.quickRecordStarted")
    static let quickRecordStopped = Notification.Name("vox.productTelemetry.quickRecordStopped")

    static func postFullPanelOpened(to center: NotificationCenter = .default) {
        center.post(name: fullPanelOpened, object: nil)
    }

    static func postQuickRecordStarted(to center: NotificationCenter = .default) {
        center.post(name: quickRecordStarted, object: nil)
    }

    static func postQuickRecordStopped(to center: NotificationCenter = .default) {
        center.post(name: quickRecordStopped, object: nil)
    }
}
