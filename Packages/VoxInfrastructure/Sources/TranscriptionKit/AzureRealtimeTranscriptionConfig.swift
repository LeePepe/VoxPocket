import Foundation

public enum RealtimeTranscriptionError: String, Error, Sendable, LocalizedError {
    case invalidConfiguration, connectionFailed, protocolRejected, invalidEvent
    case timeout, cancelled, audioOverflow, unsupportedAudio, emptyTranscript

    public var errorDescription: String? { "实时转写不可用（\(rawValue)）。" }
}

/// 实时部署独立配置，不从文件转写部署名猜测实时能力；description 不含凭据或端点。
public struct AzureRealtimeTranscriptionConfig: Sendable, CustomStringConvertible {
    let endpoint: URL
    let apiKey: String
    let deployment: String

    public init(endpoint: URL, apiKey: String, deployment: String) throws {
        guard endpoint.scheme == "https", endpoint.host?.isEmpty == false,
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              endpoint.path.isEmpty || endpoint.path == "/",
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, apiKey.count <= 8192,
              !apiKey.contains("\r"), !apiKey.contains("\n"),
              deployment.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil,
              !deployment.contains("\r"), !deployment.contains("\n") else {
            throw RealtimeTranscriptionError.invalidConfiguration
        }
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.deployment = deployment
    }

    public var description: String { "AzureRealtimeTranscriptionConfig(configured: true)" }

    func request() throws -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        components?.path = "/openai/v1/realtime"
        components?.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
        guard let url = components?.url else { throw RealtimeTranscriptionError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 8
        return request
    }
}
