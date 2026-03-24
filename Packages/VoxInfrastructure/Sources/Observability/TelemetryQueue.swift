import Foundation

/// 离线遥测事件队列
///
/// 在内存中缓存事件，支持持久化到磁盘（离线时保存，联网后重发）。
/// 使用 actor 保证线程安全。
actor TelemetryQueue {

    // MARK: - Properties

    private var pending: [TelemetryEvent] = []

    /// 磁盘持久化目录（let 常量可从 nonisolated 上下文访问）
    let storeDirectory: URL

    // MARK: - Init

    init(storeDirectory: URL? = nil) {
        if let dir = storeDirectory {
            self.storeDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.storeDirectory = appSupport
                .appendingPathComponent("VoxPocket/telemetry/pending", isDirectory: true)
        }
        // 目录不存在时创建（let 常量已初始化，可安全访问）
        try? FileManager.default.createDirectory(
            at: self.storeDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - In-memory operations

    func enqueue(_ event: TelemetryEvent) {
        pending.append(event)
    }

    /// 取出所有待发送事件并清空内存缓冲
    func takePendingEvents() -> [TelemetryEvent] {
        let events = pending
        pending = []
        return events
    }

    var pendingCount: Int { pending.count }

    // MARK: - Disk persistence

    /// 将一批事件持久化到磁盘（网络不可用时调用）
    func persistBatch(id: UUID, events: [TelemetryEvent]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(events)
        let file = storeDirectory.appendingPathComponent("\(id.uuidString).json")
        try data.write(to: file, options: .atomic)
    }

    /// 加载磁盘上所有未发送的批次，按文件创建时间升序排列
    func loadPersistedBatches() throws -> [(id: UUID, events: [TelemetryEvent])] {
        guard FileManager.default.fileExists(atPath: storeDirectory.path) else {
            return []
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .sorted { creationDate(of: $0) < creationDate(of: $1) }
            .compactMap { url -> (UUID, [TelemetryEvent])? in
                let name = url.deletingPathExtension().lastPathComponent
                guard let uuid = UUID(uuidString: name),
                      let data = try? Data(contentsOf: url),
                      let events = try? decoder.decode([TelemetryEvent].self, from: data)
                else { return nil }
                return (uuid, events)
            }
    }

    /// 删除已成功发送的批次
    func removeBatch(id: UUID) throws {
        let file = storeDirectory.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    // MARK: - Private

    private func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
    }
}
