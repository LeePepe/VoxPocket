import Foundation
import Observability

/// Azure OpenAI Whisper 转录器配置
public struct AzureWhisperConfig: Sendable {
    /// Whisper API 端点（含 api-version 查询参数）
    ///
    /// 使用 `audio/transcriptions` 保留原始语言；`audio/translations` 会强制输出英文。
    public let endpoint: URL
    /// API Key（用于 `api-key` 请求头）
    public let apiKey: String
    /// 静音超过此时长后自动停止录音（秒）；仅 AzureWhisperTranscriber 使用，0 表示禁用
    public let autoStopSilenceDuration: TimeInterval
    /// RMS 低于此值视为静音（0.0 – 1.0 归一化）；仅 AzureWhisperTranscriber 使用
    public let silenceThreshold: Float

    public init(
        endpoint: URL,
        apiKey: String,
        autoStopSilenceDuration: TimeInterval = 2.5,
        silenceThreshold: Float = 0.02
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.autoStopSilenceDuration = autoStopSilenceDuration
        self.silenceThreshold = silenceThreshold
    }
}

/// Azure OpenAI Whisper 语音转文字引擎
///
/// 纯 API 客户端：接收本地音频文件，调用 Whisper transcriptions API，返回文本。
/// 不涉及任何音频采集逻辑。
public struct WhisperEngine: Sendable {

    private let config: AzureWhisperConfig
    private let session: URLSession
    private let logger: Logger

    public init(
        config: AzureWhisperConfig,
        session: URLSession = .shared,
        logger: Logger = PrintLogger(subsystem: "WhisperEngine")
    ) {
        self.config = config
        self.session = session
        self.logger = logger
    }

    /// 转录音频文件
    ///
    /// - Parameters:
    ///   - fileURL: 本地 WAV 文件
    ///   - language: 音频语言（仅用于日志）
    /// - Returns: 转录文本
    public func transcribe(fileURL: URL, language: Locale) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)
        logger.debug("Transcribing \(audioData.count) bytes, lang: \(language.identifier)")

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendFormField(
            name: "file", filename: "audio.wav",
            contentType: "audio/wav", data: audioData, boundary: boundary
        )
        body.appendTextField(name: "response_format", value: "json", boundary: boundary)
        body.append("--\(boundary)--\r\n".utf8Data)

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "WhisperEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无效的 HTTP 响应"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("HTTP \(http.statusCode): \(body)")
            throw NSError(domain: "WhisperEngine", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Whisper API 错误 \(http.statusCode): \(body)"])
        }

        struct WhisperResponse: Decodable { let text: String }
        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        logger.info("Done: \(result.text.count) chars")
        return result.text
    }
}

// MARK: - Multipart helpers (internal to this module)

extension Data {
    mutating func appendFormField(
        name: String, filename: String,
        contentType: String, data: Data, boundary: String
    ) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8Data)
        append("Content-Type: \(contentType)\r\n\r\n".utf8Data)
        append(data)
        append("\r\n".utf8Data)
    }

    mutating func appendTextField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
        append("\(value)\r\n".utf8Data)
    }

    var utf8Data: Data { Data(self) }
}

extension String {
    var utf8Data: Data { Data(utf8) }
}
