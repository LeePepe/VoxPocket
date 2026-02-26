import Foundation

public enum PreferencesKey: String, CaseIterable, Sendable {
    case showPanelHotkey = "hotkey.showPanel"
    case quickRecordHotkey = "hotkey.quickRecord"
    case llmProvider = "llm.provider"
}

public enum PreferencesNotification {
    public static let hotkeysDidChange = Notification.Name("vox.preferences.hotkeysDidChange")
    public static let llmProviderDidChange = Notification.Name("vox.preferences.llmProviderDidChange")
}

public protocol PreferencesStore: AnyObject, Sendable {
    func getValue<T: Codable & Sendable>(for key: PreferencesKey) async -> T?
    func getValue<T: Codable & Sendable>(for key: PreferencesKey, default defaultValue: T) async -> T
    func setValue<T: Codable & Sendable>(_ value: T, for key: PreferencesKey) async
    func removeValue(for key: PreferencesKey) async
}

public actor UserDefaultsPreferencesStore: PreferencesStore {
    public static let shared = UserDefaultsPreferencesStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    public func removeValue(for key: PreferencesKey) async {
        defaults.removeObject(forKey: key.rawValue)
    }
}
