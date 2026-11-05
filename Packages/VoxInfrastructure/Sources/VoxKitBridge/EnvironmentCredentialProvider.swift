import VoxCore

/// Credentials are supplied by the app shell as an already-loaded snapshot.
public struct EnvironmentCredentialProvider: CredentialProvider, Sendable {
    private let values: [CredentialKey: Credential]
    public init(snapshot: [CredentialKey: Credential] = [:]) { self.values = snapshot }
    public func credential(for key: CredentialKey) -> Credential? { values[key] }
}
