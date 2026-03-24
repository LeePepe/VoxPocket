import Foundation

/// Loki HTTP 推送客户端
///
/// 将 TelemetryEvent 列表转换为 Loki Streams 格式并 POST 到指定端点。
/// 每种事件名对应一个独立的 stream，方便 Grafana 按标签过滤。
struct LokiShipper: Sendable {

    let endpoint: URL
    let headers: [String: String]

    init(endpoint: URL, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.headers = headers
    }

    /// 将事件批次推送到 Loki
    ///
    /// - Parameters:
    ///   - events: 待发送事件（空批次直接返回）
    ///   - appLabels: 固定标签，附加到所有 stream（如 app、env、version）
    func ship(_ events: [TelemetryEvent], appLabels: [String: String]) async throws {
        guard !events.isEmpty else { return }

        let body = try buildPushBody(events: events, appLabels: appLabels)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LokiShipperError.httpError(statusCode: code)
        }
    }

    // MARK: - Private

    private func buildPushBody(events: [TelemetryEvent], appLabels: [String: String]) throws -> Data {
        // 按事件名分组：同名事件进同一个 stream，保持 Loki 标签基数低
        let grouped = Dictionary(grouping: events) { $0.name }

        let streams: [[String: Any]] = grouped.map { name, group in
            var streamLabels = appLabels
            streamLabels["event"] = name

            // Loki values: [nanosecond_timestamp_string, log_line]
            let values: [[String]] = group.map { event in
                let nanos = String(Int64(event.timestamp.timeIntervalSince1970 * 1_000_000_000))
                let line = event.properties.isEmpty
                    ? event.name
                    : event.properties
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: " ")
                return [nanos, line]
            }

            return ["stream": streamLabels, "values": values]
        }

        return try JSONSerialization.data(withJSONObject: ["streams": streams])
    }
}

// MARK: - Errors

enum LokiShipperError: Error, LocalizedError {
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "Loki HTTP error: \(code)"
        }
    }
}
