import Foundation

enum BlobTelemetryConfigurationFailure: Equatable, Sendable {
    case invalidEndpoint
    case invalidSAS

    var diagnostic: String {
        switch self {
        case .invalidEndpoint: "blob_configuration_invalid_endpoint"
        case .invalidSAS: "blob_configuration_invalid_sas"
        }
    }
}

enum BlobTelemetryConfiguration: Equatable, Sendable {
    struct Enabled: Equatable, Sendable {
        let endpoint: URL
        let sasQuery: String

        init(endpoint: URL, sasQuery: String) {
            self.endpoint = endpoint
            self.sasQuery = sasQuery
        }
    }

    case disabled
    case invalid(BlobTelemetryConfigurationFailure)
    case enabled(Enabled)

    private init(infoDictionary: [String: Any]) {
        let endpointValue = Self.expandedValue(infoDictionary["LokiKitBlobEndpoint"])
        let sasValue = Self.expandedValue(infoDictionary["LokiKitBlobSAS"])
        guard let endpointValue, let sasValue else {
            self = .disabled
            return
        }
        guard let endpoint = URL(string: endpointValue), Self.isValidEndpoint(endpoint) else {
            self = .invalid(.invalidEndpoint)
            return
        }
        guard Self.isValidSAS(sasValue) else {
            self = .invalid(.invalidSAS)
            return
        }
        self = .enabled(Enabled(endpoint: endpoint, sasQuery: sasValue))
    }

    init() {
        self.init(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    #if DEBUG
    init(testingInfoDictionary: [String: Any]) {
        self.init(infoDictionary: testingInfoDictionary)
    }

    init(testingBundle: Bundle) {
        self.init(infoDictionary: testingBundle.infoDictionary ?? [:])
    }
    #endif

    var diagnostic: String {
        switch self {
        case .disabled: "blob_configuration_disabled"
        case .invalid(let failure): failure.diagnostic
        case .enabled: "blob_configuration_enabled"
        }
    }

    private static func expandedValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func isValidEndpoint(_ endpoint: URL) -> Bool {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { return false }
        return components.percentEncodedPath.range(
            of: #"^/[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$"#,
            options: .regularExpression
        ) != nil && !components.path.contains("--")
    }

    private static func isValidSAS(_ value: String) -> Bool {
        let query = value.hasPrefix("?") ? String(value.dropFirst()) : value
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/?%"
        )
        guard !query.isEmpty,
              query.removingPercentEncoding != nil,
              query.rangeOfCharacter(from: allowed.inverted) == nil
        else { return false }
        var components = URLComponents()
        components.percentEncodedQuery = query
        guard let items = components.queryItems, !items.isEmpty else { return false }

        let names = items.map(\.name)
        let supported: Set<String> = ["sv", "sr", "si", "sp", "st", "se", "spr", "sip", "sig"]
        guard Set(names).count == names.count, Set(names).isSubset(of: supported) else { return false }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard fields["sr"] == "c",
              fields["si"]?.isEmpty == false,
              fields["sig"]?.isEmpty == false,
              fields["spr"] == "https"
        else { return false }
        return fields["sp"].map { $0 == "c" } ?? true
    }
}
