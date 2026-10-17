import Foundation
import Preferences

@MainActor
public final class ProductTelemetrySettingsViewModel: ObservableObject {
    public static let consentDidChange = Notification.Name("vox.productTelemetry.consentDidChange")
    public static let settingsDidOpen = Notification.Name("vox.productTelemetry.settingsDidOpen")

    @Published public private(set) var isSendingUsageData = false
    @Published public private(set) var isLoaded = false

    private let preferences: ProductTelemetryPreferences
    private let onConsentChanged: @MainActor @Sendable (Bool) async -> Void
    private let notificationCenter: NotificationCenter
    private let readConsent: @MainActor @Sendable () async -> Bool
    private var consentObservation: Task<Void, Never>?
    private var intentGeneration: UInt64 = 0
    private var refreshGeneration: UInt64 = 0

    public convenience init(
        preferences: ProductTelemetryPreferences = ProductTelemetryPreferences()
    ) {
        self.init(
            preferences: preferences,
            notificationCenter: .default,
            readConsent: { await preferences.isConsented },
            onConsentChanged: {
            await ProductTelemetrySettingsViewModel.notifyConsentChanged(
                $0,
                notificationCenter: .default
            )
            }
        )
    }

    public convenience init(
        preferences: ProductTelemetryPreferences,
        onConsentChanged: @escaping @MainActor @Sendable (Bool) async -> Void
    ) {
        self.init(
            preferences: preferences,
            notificationCenter: .default,
            readConsent: { await preferences.isConsented },
            onConsentChanged: onConsentChanged
        )
    }

    init(
        preferences: ProductTelemetryPreferences,
        notificationCenter: NotificationCenter,
        readConsent: @escaping @MainActor @Sendable () async -> Bool,
        onConsentChanged: @escaping @MainActor @Sendable (Bool) async -> Void
    ) {
        self.preferences = preferences
        self.notificationCenter = notificationCenter
        self.readConsent = readConsent
        self.onConsentChanged = onConsentChanged
        observeCommittedConsent()
    }

    deinit {
        consentObservation?.cancel()
    }

    private static func notifyConsentChanged(
        _ consent: Bool,
        notificationCenter: NotificationCenter
    ) async {
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        notificationCenter.post(
            name: consentDidChange,
            object: nil,
            userInfo: [
                "isConsented": consent,
                "transitionCompletion": continuation
            ]
        )
        for await _ in completion {}
    }

    public func load() async {
        let generation = beginRefresh()
        let intent = intentGeneration
        let consent = await readConsent()
        guard refreshGeneration == generation, intentGeneration == intent else { return }
        isSendingUsageData = consent
        isLoaded = true
    }

    public func setSendingUsageData(_ isEnabled: Bool) async {
        intentGeneration &+= 1
        refreshGeneration &+= 1
        let intent = intentGeneration
        await onConsentChanged(isEnabled)
        let committed = await readConsent()
        guard intentGeneration == intent, committed == isEnabled else { return }
        refreshGeneration &+= 1
        isSendingUsageData = committed
        notificationCenter.post(name: Self.consentDidChange, object: nil)
    }

    private func observeCommittedConsent() {
        consentObservation = Task { @MainActor [weak self, notificationCenter] in
            for await notification in notificationCenter.notifications(
                named: Self.consentDidChange
            ) {
                guard notification.userInfo == nil else { continue }
                await self?.refreshCommittedConsent()
            }
        }
    }

    private func refreshCommittedConsent() async {
        guard isLoaded else { return }
        let generation = beginRefresh()
        let intent = intentGeneration
        let committed = await readConsent()
        guard refreshGeneration == generation, intentGeneration == intent else { return }
        isSendingUsageData = committed
    }

    private func beginRefresh() -> UInt64 {
        refreshGeneration &+= 1
        return refreshGeneration
    }
}
