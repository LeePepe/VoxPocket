import Foundation

public enum PrivateModelConfigurationError: String, Error, Sendable, LocalizedError {
    case unreadable, unsafeFile, oversized, invalidJSON, invalidFields

    public var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取本机模型配置。请检查沙箱配置路径。"
        case .unsafeFile: "本机模型配置必须为当前用户所有的普通文件，权限为 0600。"
        case .oversized: "本机模型配置不能超过 64 KiB。"
        case .invalidJSON: "本机模型配置不是有效 JSON；请参考 config.example.json。"
        case .invalidFields: "请检查本机模型配置中的 HTTPS 根地址、密钥和部署名。"
        }
    }
}

/// 仅允许四个 Azure 配置字段；不承载任意环境设置或文件路径。
struct PrivateModelConfiguration: Decodable, Sendable {
    struct Azure: Decodable, Sendable {
        let endpoint: String
        let apiKey: String
        let transcriptionDeployment: String
        let refinementDeployment: String
    }
    let azure: Azure

    static func decode(_ data: Data) throws -> PrivateModelConfiguration {
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw PrivateModelConfigurationError.invalidJSON }
    }

    func environmentDefaults() throws -> [String: String] {
        let endpoint = azure.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = azure.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), url.scheme == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              !key.isEmpty, !key.contains("\n"), !key.contains("\r"), key.count <= 8192,
              validDeployment(azure.transcriptionDeployment), validDeployment(azure.refinementDeployment) else {
            throw PrivateModelConfigurationError.invalidFields
        }
        // 文件默认值采用旧别名，使显式共享密钥或各工作负载的环境覆盖仍优先。
        return [
            "AZURE_OPENAI_ENDPOINT": url.absoluteString,
            "whisperkey": key,
            "kimikey": key,
            "AZURE_TRANSCRIPTION_DEPLOYMENT": azure.transcriptionDeployment,
            "AZURE_FOUNDRY_MODEL": azure.refinementDeployment
        ]
    }

    private func validDeployment(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil
            && !value.contains("\n") && !value.contains("\r")
    }
}

public struct ModelRuntimeConfiguration: Sendable, CustomStringConvertible {
    public let environmentValues: [String: String]
    public let loadedPrivateFile: Bool

    public var description: String { "ModelRuntimeConfiguration(privateFile: \(loadedPrivateFile))" }
}
