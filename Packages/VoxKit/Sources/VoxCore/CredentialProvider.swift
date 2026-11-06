import Foundation

public struct Credential: Sendable, Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var isEmpty: Bool { rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var description: String { "Credential(<redacted>)" }
    public var debugDescription: String { "Credential(<redacted>)" }
    public var customMirror: Mirror { Mirror(self, children: EmptyCollection()) }
}

public struct CredentialKey: Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let azureSpeechKey = Self(rawValue: "azureSpeechKey")
    public static let azureFoundryAPIKey = Self(rawValue: "azureFoundryAPIKey")
    public static let whisperKey = Self(rawValue: "whisperKey")
    public static let llmAPIKey = Self(rawValue: "llmAPIKey")
}

public protocol CredentialProvider: Sendable {
    func credential(for key: CredentialKey) -> Credential?
}

public struct NoopCredentialProvider: CredentialProvider, Sendable {
    public init() {}
    public func credential(for key: CredentialKey) -> Credential? { nil }
}
