#if os(macOS)
import Foundation
import Preferences
import SwiftUI
import Testing
@testable import UIShared

@MainActor
struct ProductTelemetrySettingsViewTests {
    @Test func macOSAndCrossPlatformPrivacySurfacesUseExactControlWithoutReset() async {
        let suite = "ProductTelemetrySettingsViewTests.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = ProductTelemetryPreferences(
            store: UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        )
        let model = ProductTelemetrySettingsViewModel(
            preferences: preferences,
            onConsentChanged: { _ in }
        )
        await model.load()

        let settings = ProductTelemetrySettingsView(viewModel: model)
        let privacy = PrivacyCard(productTelemetry: model)

        #expect(!settings.consentBinding.wrappedValue)
        #expect(!privacy.consentBinding.wrappedValue)
        #expect(String(describing: settings.body).contains("Send usage data"))
        #expect(String(describing: privacy.body).contains("Send usage data"))
        #expect(!String(describing: settings.body).localizedCaseInsensitiveContains("reset"))
        #expect(!String(describing: privacy.body).localizedCaseInsensitiveContains("rotate"))
    }
}
#endif
