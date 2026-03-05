import Foundation
import Preferences

public enum LLMProviderSelection: String, CaseIterable, Codable, Sendable {
    case appleIntelligence
    case azureFoundry

    public var displayName: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .azureFoundry:
            return "Azure Foundry"
        }
    }
}

@MainActor
public final class LLMProviderSettingsViewModel: ObservableObject {
    @Published public var selectedProvider: LLMProviderSelection = .appleIntelligence
    @Published public var skipContentAnalysis: Bool = false

    private let preferences: UserDefaultsPreferencesStore

    public init(preferences: UserDefaultsPreferencesStore = .shared) {
        self.preferences = preferences
    }

    public func load() async {
        let stored: String = await preferences.getValue(
            for: .llmProvider,
            default: LLMProviderSelection.appleIntelligence.rawValue
        )
        selectedProvider = LLMProviderSelection(rawValue: stored) ?? .appleIntelligence
        skipContentAnalysis = await preferences.getValue(for: .llmSkipContentAnalysis, default: false)
    }

    public func updateProvider(_ provider: LLMProviderSelection) async {
        selectedProvider = provider
        await preferences.setValue(provider.rawValue, for: .llmProvider)
        NotificationCenter.default.post(name: PreferencesNotification.llmProviderDidChange, object: nil)
    }

    public func updateSkipContentAnalysis(_ skip: Bool) async {
        skipContentAnalysis = skip
        await preferences.setValue(skip, for: .llmSkipContentAnalysis)
        NotificationCenter.default.post(name: PreferencesNotification.llmAnalysisSettingsDidChange, object: nil)
    }
}
