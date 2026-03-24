import Foundation

/// 基于 Loki 的遥测服务
///
/// 将事件批量上报到 Grafana Loki，支持离线缓存：
/// - 事件先积攒在内存队列中
/// - `flush()` 时尝试 HTTP 上报；网络不可用则持久化到磁盘
/// - 下次 `flush()` 时自动重传磁盘中的历史批次
///
/// 本地开发对接 Docker Loki，上架后切换 endpoint 到 Grafana Cloud（API 完全兼容）。
public final class LokiTelemetryService: TelemetryService, @unchecked Sendable {

    // MARK: - TelemetryService

    public var isEnabled: Bool

    // MARK: - Private

    private let queue: TelemetryQueue
    private let shipper: LokiShipper
    private let appLabels: [String: String]

    // MARK: - Init

    /// - Parameters:
    ///   - endpoint: Loki push 端点（本地 Docker: `http://localhost:3100/loki/api/v1/push`）
    ///   - appLabels: 固定标签（app 默认已填充，可追加 env、version 等）
    ///   - isEnabled: 是否启用，默认 true
    ///   - authToken: Bearer token（Grafana Cloud 使用 `<user>:<apikey>` base64 编码）
    ///   - storeDirectory: 离线队列目录，nil 使用默认 Application Support 路径
    public init(
        endpoint: URL,
        appLabels: [String: String] = [:],
        isEnabled: Bool = true,
        authToken: String? = nil,
        storeDirectory: URL? = nil
    ) {
        self.isEnabled = isEnabled
        self.queue = TelemetryQueue(storeDirectory: storeDirectory)

        var headers: [String: String] = [:]
        if let token = authToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        self.shipper = LokiShipper(endpoint: endpoint, headers: headers)

        var labels = appLabels
        if labels["app"] == nil { labels["app"] = "VoxPocket" }
        self.appLabels = labels
    }

    // MARK: - TelemetryService

    public func track(_ event: TelemetryEvent) {
        guard isEnabled else { return }
        Task { await queue.enqueue(event) }
    }

    public func track(name: String, properties: [String: String]) {
        track(TelemetryEvent(name: name, properties: properties))
    }

    /// 将所有待发送事件上报到 Loki
    ///
    /// 执行顺序：
    /// 1. 先重试磁盘上遗留的历史批次（按时间升序，网络失败则停止）
    /// 2. 再发送本次内存中积攒的事件
    /// 3. 发送失败则持久化到磁盘等待下次重试
    public func flush() async {
        guard isEnabled else { return }

        // 1. 重试历史批次
        if let persisted = try? await queue.loadPersistedBatches() {
            for batch in persisted {
                do {
                    try await shipper.ship(batch.events, appLabels: appLabels)
                    try? await queue.removeBatch(id: batch.id)
                } catch {
                    break // 网络不通，保留磁盘文件，下次再试
                }
            }
        }

        // 2. 取出当前内存事件
        let pending = await queue.takePendingEvents()
        guard !pending.isEmpty else { return }

        // 3. 尝试发送，失败则持久化
        do {
            try await shipper.ship(pending, appLabels: appLabels)
        } catch {
            let batchId = UUID()
            try? await queue.persistBatch(id: batchId, events: pending)
        }
    }

    public func resetIdentifier() {}
}
