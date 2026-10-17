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
    private var requestGeneration: UInt64 = 0

    public init(preferences: ProductTelemetryPreferences = ProductTelemetryPreferences()) {
        self.preferences = preferences
        onConsentChanged = {
            await ProductTelemetrySettingsViewModel.notifyConsentChanged(
                $0,
                notificationCenter: .default
            )
        }
    }

    public init(
        preferences: ProductTelemetryPreferences,
        onConsentChanged: @escaping @MainActor @Sendable (Bool) async -> Void
    ) {
        self.preferences = preferences
        self.onConsentChanged = onConsentChanged
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
        isSendingUsageData = await preferences.isConsented
        isLoaded = true
    }

    public func setSendingUsageData(_ isEnabled: Bool) async {
        requestGeneration &+= 1
        let request = requestGeneration
        await onConsentChanged(isEnabled)
        guard requestGeneration == request else { return }
        isSendingUsageData = isEnabled
    }
}
