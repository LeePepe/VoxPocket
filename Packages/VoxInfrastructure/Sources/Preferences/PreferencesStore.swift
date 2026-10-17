import Foundation

public enum PreferencesKey: String, CaseIterable, Sendable {
    case showPanelHotkey = "hotkey.showPanel"
    case quickRecordHotkey = "hotkey.quickRecord"
    case llmProvider = "llm.provider"
    case llmSkipContentAnalysis = "llm.skipContentAnalysis"
    case speechModel = "model.speech"
    case intentModel = "model.intent"
    case toneModel = "model.tone"
    case realtimeDeployment = "model.realtimeDeployment"
    case productTelemetryConsent = "telemetry.product.consent"
}

public actor ProductTelemetryPreferences {
    private let store: UserDefaultsPreferencesStore
    private let identityGenerator: @Sendable () -> UUID
    private var lastMutation: Task<UUID?, Never>?

    public init(store: UserDefaultsPreferencesStore = .shared) {
        self.store = store
        identityGenerator = { UUID() }
    }

#if DEBUG
    init(
        store: UserDefaultsPreferencesStore,
        identityGenerator: @escaping @Sendable () -> UUID
    ) {
        self.store = store
        self.identityGenerator = identityGenerator
    }
#endif

    public var isConsented: Bool {
        get async {
            _ = await lastMutation?.value
            let consent: Bool? = await store.getValue(for: .productTelemetryConsent)
            return consent ?? false
        }
    }

    @discardableResult
    public func setConsent(_ isConsented: Bool) async -> UUID? {
        let previous = lastMutation
        let store = store
        let identityGenerator = identityGenerator
        let mutation = Task<UUID?, Never> {
            _ = await previous?.value
            guard isConsented else {
                await store.setValue(false, for: .productTelemetryConsent)
                return nil
            }
            let identity = await store.productTelemetryInstallIdentity(
                creatingWith: identityGenerator
            )
            await store.setValue(true, for: .productTelemetryConsent)
            return identity
        }
        lastMutation = mutation
        return await mutation.value
    }

    public func persistConsent(_ isConsented: Bool) async {
        let previous = lastMutation
        let store = store
        let mutation = Task<UUID?, Never> {
            _ = await previous?.value
            await store.setValue(isConsented, for: .productTelemetryConsent)
            return nil
        }
        lastMutation = mutation
        _ = await mutation.value
    }

    public func installIdentityIfConsented() async -> UUID? {
        let previous = lastMutation
        let store = store
        let identityGenerator = identityGenerator
        let mutation = Task<UUID?, Never> {
            _ = await previous?.value
            let consent: Bool? = await store.getValue(for: .productTelemetryConsent)
            guard consent == true else { return nil }
            return await store.productTelemetryInstallIdentity(
                creatingWith: identityGenerator
            )
        }
        lastMutation = mutation
        return await mutation.value
    }
}

public enum PreferencesNotification {
    public static let hotkeysDidChange = Notification.Name("vox.preferences.hotkeysDidChange")
    public static let llmProviderDidChange = Notification.Name("vox.preferences.llmProviderDidChange")
    public static let llmAnalysisSettingsDidChange = Notification.Name("vox.preferences.llmAnalysisSettingsDidChange")
    public static let stageModelsDidChange = Notification.Name("vox.preferences.stageModelsDidChange")
}

public protocol PreferencesStore: AnyObject, Sendable {
    func getValue<T: Codable & Sendable>(for key: PreferencesKey) async -> T?
    func getValue<T: Codable & Sendable>(for key: PreferencesKey, default defaultValue: T) async -> T
    func setValue<T: Codable & Sendable>(_ value: T, for key: PreferencesKey) async
    func removeValue(for key: PreferencesKey) async
}

public actor UserDefaultsPreferencesStore: PreferencesStore {
    public static let shared = UserDefaultsPreferencesStore()

    private static let productTelemetryInstallIdentityKey = "telemetry.product.installIdentity"
    private let defaults: UserDefaults
    private let productTelemetryConsentWriteGate: (@Sendable (Bool) async -> Void)?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        productTelemetryConsentWriteGate = nil
    }

#if DEBUG
    init(
        defaults: UserDefaults,
        productTelemetryConsentWriteGate: @escaping @Sendable (Bool) async -> Void
    ) {
        self.defaults = defaults
        self.productTelemetryConsentWriteGate = productTelemetryConsentWriteGate
    }
#endif

    public func getValue<T: Codable & Sendable>(for key: PreferencesKey) async -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    public func getValue<T: Codable & Sendable>(for key: PreferencesKey, default defaultValue: T) async -> T {
        if let value: T = await getValue(for: key) {
            return value
        }
        await setValue(defaultValue, for: key)
        return defaultValue
    }

    public func setValue<T: Codable & Sendable>(_ value: T, for key: PreferencesKey) async {
        if key == .productTelemetryConsent,
           let consent = value as? Bool {
            await productTelemetryConsentWriteGate?(consent)
        }
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    public func removeValue(for key: PreferencesKey) async {
        defaults.removeObject(forKey: key.rawValue)
    }

    fileprivate var productTelemetryInstallIdentity: UUID? {
        guard let data = defaults.data(forKey: Self.productTelemetryInstallIdentityKey) else {
            return nil
        }
        return try? decoder.decode(UUID.self, from: data)
    }

    fileprivate func productTelemetryInstallIdentity(
        creatingWith identityGenerator: @Sendable () -> UUID
    ) -> UUID {
        if let identity = productTelemetryInstallIdentity {
            return identity
        }
        let identity = identityGenerator()
        if let data = try? encoder.encode(identity) {
            defaults.set(data, forKey: Self.productTelemetryInstallIdentityKey)
        }
        return identity
    }
}
