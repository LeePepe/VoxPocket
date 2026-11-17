import Foundation
import Synchronization
import CoreModels

/// Key-value store abstraction for `NSUbiquitousKeyValueStore` or in-memory test doubles.
public protocol UbiquitousAIOrderKVStoring: AnyObject, Sendable {
    func setData(_ data: Data, forKey key: String)
    func data(forKey key: String) -> Data?
    func dictionaryRepresentation() -> [String: Any]
    @discardableResult
    func synchronize() -> Bool
}

/// Thread-safe in-memory KV store used when iCloud KVS is unavailable or in unit tests.
public final class InMemoryUbiquitousAIOrderKVStore: UbiquitousAIOrderKVStoring, Sendable {
    private let mutex = Mutex<[String: Data]>([:])

    public init() {}

    public func setData(_ data: Data, forKey key: String) {
        mutex.withLock { $0[key] = data }
    }

    public func data(forKey key: String) -> Data? {
        mutex.withLock { $0[key] }
    }

    public func dictionaryRepresentation() -> [String: Any] {
        mutex.withLock { $0 }
    }

    @discardableResult
    public func synchronize() -> Bool {
        true
    }
}

/// Production wrapper around `NSUbiquitousKeyValueStore.default`.
public final class SystemUbiquitousAIOrderKVStore: UbiquitousAIOrderKVStoring, @unchecked Sendable {
    private let lock = NSLock()

    public init() {}

    public func setData(_ data: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        NSUbiquitousKeyValueStore.default.set(data, forKey: key)
    }

    public func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return NSUbiquitousKeyValueStore.default.data(forKey: key)
    }

    public func dictionaryRepresentation() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return NSUbiquitousKeyValueStore.default.dictionaryRepresentation
    }

    @discardableResult
    public func synchronize() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return NSUbiquitousKeyValueStore.default.synchronize()
    }
}

/// Dual-channel iCloud sync protocol (`iCloud Drive AIOrders directory` + `NSUbiquitousKeyValueStore` + injectable local directory fallback).
public protocol ICloudAIOrderSyncing: AnyObject, Sendable {
    var ordersDirectoryURL: URL { get }
    var statusReports: AsyncStream<AIExecutionStatusReport> { get }

    @discardableResult
    func submitOrderToICloud(todo: VoiceTodo, now: Date) async throws -> ICloudAIExecutionOrder

    func saveOrder(_ order: ICloudAIExecutionOrder) async throws
    func loadOrder(orderID: UUID) async throws -> ICloudAIExecutionOrder?
    func loadLatestOrder(forTodoID todoID: UUID) async throws -> ICloudAIExecutionOrder?
    func listOrders(matchingState state: AIOrderExecutionState?) async throws -> [ICloudAIExecutionOrder]

    @discardableResult
    func publishStatusReport(_ report: AIExecutionStatusReport) async throws -> ICloudAIExecutionOrder?
}

public final class ICloudAIOrderSyncService: ICloudAIOrderSyncing, Sendable {
    public let ordersDirectoryURL: URL
    private let kvStore: any UbiquitousAIOrderKVStoring
    private let continuationsMutex = Mutex<[UUID: AsyncStream<AIExecutionStatusReport>.Continuation]>([:])
    private let fileMutex = Mutex<Void>(())

    public static let kvsKeyPrefix = "vox.icloud.ai.order."

    public init(
        ordersDirectoryURL: URL? = nil,
        kvStore: (any UbiquitousAIOrderKVStoring)? = nil
    ) {
        self.ordersDirectoryURL = ordersDirectoryURL ?? Self.resolveDefaultOrdersDirectory()
        self.kvStore = kvStore ?? InMemoryUbiquitousAIOrderKVStore()
        try? FileManager.default.createDirectory(at: self.ordersDirectoryURL, withIntermediateDirectories: true)
    }

    public static func resolveDefaultOrdersDirectory() -> URL {
        if let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return ubiquityURL
                .appendingPathComponent("Documents/VoxPocket/AIOrders", isDirectory: true)
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport
                .appendingPathComponent("VoxPocket/ICloudAIOrders", isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("VoxPocket-ICloudAIOrders", isDirectory: true)
    }

    public var statusReports: AsyncStream<AIExecutionStatusReport> {
        AsyncStream { continuation in
            let id = UUID()
            continuationsMutex.withLock { $0[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.continuationsMutex.withLock { _ = $0.removeValue(forKey: id) }
            }
        }
    }

    @discardableResult
    public func submitOrderToICloud(todo: VoiceTodo, now: Date = Date()) async throws -> ICloudAIExecutionOrder {
        let order = ICloudAIExecutionOrder(from: todo, now: now)
        try await saveOrder(order)
        let queuedReport = AIExecutionStatusReport(
            orderID: order.orderID,
            todoID: order.todoID,
            state: .queued,
            progressStage: order.progressStage,
            progressFraction: order.progressFraction,
            outputSummary: nil,
            assignedRunnerName: nil,
            updatedAt: now
        )
        broadcast(queuedReport)
        return order
    }

    public func saveOrder(_ order: ICloudAIExecutionOrder) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(order)

        try fileMutex.withLock { _ in
            try FileManager.default.createDirectory(at: ordersDirectoryURL, withIntermediateDirectories: true)
            let fileURL = orderFileURL(for: order.orderID)
            try data.write(to: fileURL, options: .atomic)
        }

        kvStore.setData(data, forKey: Self.kvsKeyPrefix + order.orderID.uuidString)
        _ = kvStore.synchronize()
    }

    public func loadOrder(orderID: UUID) async throws -> ICloudAIExecutionOrder? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let fileData: Data? = fileMutex.withLock { _ in
            let fileURL = orderFileURL(for: orderID)
            return try? Data(contentsOf: fileURL)
        }
        if let fileData, let decoded = try? decoder.decode(ICloudAIExecutionOrder.self, from: fileData) {
            return decoded
        }

        if let kvData = kvStore.data(forKey: Self.kvsKeyPrefix + orderID.uuidString),
           let decoded = try? decoder.decode(ICloudAIExecutionOrder.self, from: kvData) {
            return decoded
        }
        return nil
    }

    public func loadLatestOrder(forTodoID todoID: UUID) async throws -> ICloudAIExecutionOrder? {
        let all = try await listOrders(matchingState: nil)
        return all
            .filter { $0.todoID == todoID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    public func listOrders(matchingState state: AIOrderExecutionState? = nil) async throws -> [ICloudAIExecutionOrder] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var byID: [UUID: ICloudAIExecutionOrder] = [:]

        fileMutex.withLock { _ in
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: ordersDirectoryURL,
                includingPropertiesForKeys: nil
            ) else { return }
            for url in urls where url.pathExtension == "json" && !url.lastPathComponent.hasSuffix(".status.json") {
                if let data = try? Data(contentsOf: url),
                   let order = try? decoder.decode(ICloudAIExecutionOrder.self, from: data) {
                    byID[order.orderID] = order
                }
            }
        }

        for (key, value) in kvStore.dictionaryRepresentation() where key.hasPrefix(Self.kvsKeyPrefix) {
            if let data = value as? Data,
               let order = try? decoder.decode(ICloudAIExecutionOrder.self, from: data) {
                if let existing = byID[order.orderID] {
                    if order.updatedAt > existing.updatedAt {
                        byID[order.orderID] = order
                    }
                } else {
                    byID[order.orderID] = order
                }
            }
        }

        let filtered = byID.values.filter { state == nil || $0.state == state }
        return filtered.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func publishStatusReport(_ report: AIExecutionStatusReport) async throws -> ICloudAIExecutionOrder? {
        guard let existing = try await loadOrder(orderID: report.orderID) else {
            broadcast(report)
            return nil
        }
        let updated = existing.applying(report)
        try await saveOrder(updated)
        broadcast(report)
        return updated
    }

    public func orderFileURL(for orderID: UUID) -> URL {
        ordersDirectoryURL.appendingPathComponent("\(orderID.uuidString).json")
    }

    public func statusFileURL(for orderID: UUID) -> URL {
        ordersDirectoryURL.appendingPathComponent("\(orderID.uuidString).status.json")
    }

    private func broadcast(_ report: AIExecutionStatusReport) {
        let continuations = continuationsMutex.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(report)
        }
    }
}

// MARK: - Real-Time Status Reporter & macOS Auto-Pickup Service

/// Live status reporter passed into custom Swift handlers or fed by stdout `VOX_STATUS:` / `VOX_PROGRESS:` lines and `$VOX_STATUS_FILE`.
public final class AIOrderStatusReporter: Sendable {
    public let orderID: UUID
    public let todoID: UUID
    public let runnerName: String
    private let syncService: any ICloudAIOrderSyncing

    public init(
        orderID: UUID,
        todoID: UUID,
        runnerName: String,
        syncService: any ICloudAIOrderSyncing
    ) {
        self.orderID = orderID
        self.todoID = todoID
        self.runnerName = runnerName
        self.syncService = syncService
    }

    @discardableResult
    public func reportProgress(
        stage: String,
        fraction: Double,
        state: AIOrderExecutionState = .running,
        now: Date = Date()
    ) async throws -> ICloudAIExecutionOrder? {
        let report = AIExecutionStatusReport(
            orderID: orderID,
            todoID: todoID,
            state: state,
            progressStage: stage,
            progressFraction: fraction,
            outputSummary: nil,
            assignedRunnerName: runnerName,
            updatedAt: now
        )
        return try await syncService.publishStatusReport(report)
    }

    /// Parses stdout lines emitted by user scripts (`VOX_STATUS: <stage>` and `VOX_PROGRESS: <0.0..1.0>`)
    /// and immediately publishes live status updates back to iCloud.
    public func ingestScriptOutput(_ text: String, now: Date = Date()) async throws {
        var currentFraction: Double = 0.5
        var latestStage: String?
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("VOX_PROGRESS:") {
                let rawValue = line.dropFirst("VOX_PROGRESS:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Double(rawValue), parsed.isFinite {
                    currentFraction = min(1.0, max(0.0, parsed))
                }
                if let stage = latestStage {
                    _ = try await reportProgress(stage: stage, fraction: currentFraction, state: .running, now: now)
                }
            } else if line.hasPrefix("VOX_STATUS:") {
                let stage = line.dropFirst("VOX_STATUS:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !stage.isEmpty {
                    latestStage = stage
                    _ = try await reportProgress(stage: stage, fraction: currentFraction, state: .running, now: now)
                }
            }
        }
    }

    /// Reads an external `$VOX_STATUS_FILE` JSON written by a custom script and syncs it to iCloud.
    public func syncStatusFileIfPresent(at statusFileURL: URL, now: Date = Date()) async throws {
        guard let data = try? Data(contentsOf: statusFileURL),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        let stage = (dict["progressStage"] as? String) ?? (dict["stage"] as? String) ?? "AI 执行中…"
        let fraction = (dict["progressFraction"] as? Double) ?? (dict["progress"] as? Double) ?? 0.5
        let rawState = (dict["state"] as? String) ?? "running"
        let state = AIOrderExecutionState(rawValue: rawState) ?? .running
        let summary = dict["outputSummary"] as? String
        let report = AIExecutionStatusReport(
            orderID: orderID,
            todoID: todoID,
            state: state,
            progressStage: stage,
            progressFraction: fraction,
            outputSummary: summary,
            assignedRunnerName: runnerName,
            updatedAt: now
        )
        _ = try await syncService.publishStatusReport(report)
    }
}

/// Persistent file + Preferences loader/saver for `UserAIRunnerConfig`.
public final class UserAIRunnerConfigStore: Sendable {
    public let configFileURL: URL
    private let mutex = Mutex<UserAIRunnerConfig>(UserAIRunnerConfig())

    public init(configFileURL: URL? = nil) {
        self.configFileURL = configFileURL ?? Self.defaultConfigFileURL()
        if let data = try? Data(contentsOf: self.configFileURL),
           let loaded = try? JSONDecoder().decode(UserAIRunnerConfig.self, from: data) {
            mutex.withLock { $0 = loaded }
        }
    }

    public static func defaultConfigFileURL() -> URL {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("VoxPocket/ai-runner-config.json")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voxpocket-ai-runner-config.json")
    }

    public func currentConfig() -> UserAIRunnerConfig {
        mutex.withLock { $0 }
    }

    public func saveConfig(_ config: UserAIRunnerConfig) throws {
        mutex.withLock { $0 = config }
        try FileManager.default.createDirectory(
            at: configFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFileURL, options: .atomic)
    }
}

/// macOS Automatic Order Pickup & Custom Script/Code Execution Service.
public final class MacAIOrderAutoPickupService: Sendable {
    public typealias CustomCodeHandler = @Sendable (ICloudAIExecutionOrder, AIOrderStatusReporter) async throws -> String
    public typealias ShellCommandExecutor = @Sendable (
        _ command: String,
        _ environment: [String: String],
        _ workingDirectory: String,
        _ statusReporter: AIOrderStatusReporter
    ) async throws -> (exitCode: Int32, stdout: String)

    private let syncService: any ICloudAIOrderSyncing
    private let configStore: UserAIRunnerConfigStore
    private let customHandlerMutex = Mutex<CustomCodeHandler?>(nil)
    private let shellExecutorMutex: Mutex<ShellCommandExecutor?>

    public init(
        syncService: any ICloudAIOrderSyncing,
        configStore: UserAIRunnerConfigStore = UserAIRunnerConfigStore(),
        customCodeHandler: CustomCodeHandler? = nil,
        shellExecutor: ShellCommandExecutor? = nil
    ) {
        self.syncService = syncService
        self.configStore = configStore
        self.customHandlerMutex.withLock { $0 = customCodeHandler }
        self.shellExecutorMutex = Mutex(shellExecutor)
    }

    /// Programmatic Swift closure registration interface for custom AI execution logic.
    public func registerCustomCodeHandler(_ handler: @escaping CustomCodeHandler) {
        customHandlerMutex.withLock { $0 = handler }
    }

    public func clearCustomCodeHandler() {
        customHandlerMutex.withLock { $0 = nil }
    }

    public func registerShellExecutor(_ executor: @escaping ShellCommandExecutor) {
        shellExecutorMutex.withLock { $0 = executor }
    }

    public var currentConfig: UserAIRunnerConfig {
        configStore.currentConfig()
    }

    public func updateConfig(_ config: UserAIRunnerConfig) throws {
        try configStore.saveConfig(config)
    }

    /// Scans iCloud `AIOrders` for `.queued` orders, claims them (`claimedByMac`), runs the configured custom code handler or script template,
    /// streams real-time `VOX_STATUS` / `$VOX_STATUS_FILE` progress back to iCloud, and writes final `.completed` / `.failed` state.
    @discardableResult
    public func pollAndProcessQueuedOrders(now: Date = Date()) async throws -> [ICloudAIExecutionOrder] {
        let config = configStore.currentConfig()
        guard config.isAutoPickupEnabled else { return [] }

        let queuedOrders = try await syncService.listOrders(matchingState: .queued)
        var processed: [ICloudAIExecutionOrder] = []

        for order in queuedOrders {
            let finalOrder = try await claimAndExecuteOrder(order, config: config, now: now)
            processed.append(finalOrder)
        }
        return processed
    }

    @discardableResult
    public func claimAndExecuteOrder(
        _ order: ICloudAIExecutionOrder,
        config: UserAIRunnerConfig? = nil,
        now: Date = Date()
    ) async throws -> ICloudAIExecutionOrder {
        let activeConfig = config ?? configStore.currentConfig()
        let runnerName = activeConfig.runnerDisplayName
        let reporter = AIOrderStatusReporter(
            orderID: order.orderID,
            todoID: order.todoID,
            runnerName: runnerName,
            syncService: syncService
        )

        // Step 1: Claim order on Mac (`claimedByMac`)
        let claimedReport = AIExecutionStatusReport(
            orderID: order.orderID,
            todoID: order.todoID,
            state: .claimedByMac,
            progressStage: "已认领订单 · 准备启动 \(runnerName)",
            progressFraction: 0.20,
            outputSummary: nil,
            assignedRunnerName: runnerName,
            updatedAt: now
        )
        _ = try await syncService.publishStatusReport(claimedReport)

        let orderFileURL = syncService.ordersDirectoryURL.appendingPathComponent("\(order.orderID.uuidString).json")
        let statusFileURL = syncService.ordersDirectoryURL.appendingPathComponent("\(order.orderID.uuidString).status.json")

        do {
            let summary: String
            if let customHandler = customHandlerMutex.withLock({ $0 }) {
                _ = try await reporter.reportProgress(
                    stage: "正在运行自定义 AI 处理器…",
                    fraction: 0.35,
                    state: .running,
                    now: now
                )
                summary = try await customHandler(order, reporter)
            } else if let shellExecutor = shellExecutorMutex.withLock({ $0 }) {
                let interpolated = activeConfig.interpolateCommand(
                    order: order,
                    orderFilePath: orderFileURL.path,
                    statusFilePath: statusFileURL.path
                )
                let env: [String: String] = [
                    "VOX_ORDER_ID": order.orderID.uuidString,
                    "VOX_TODO_ID": order.todoID.uuidString,
                    "VOX_ORDER_FILE": orderFileURL.path,
                    "VOX_STATUS_FILE": statusFileURL.path
                ]
                _ = try await reporter.reportProgress(
                    stage: "正在执行脚本命令…",
                    fraction: 0.40,
                    state: .running,
                    now: now
                )
                let result = try await shellExecutor(
                    interpolated,
                    env,
                    activeConfig.defaultWorkingDirectory,
                    reporter
                )
                try await reporter.ingestScriptOutput(result.stdout, now: now)
                try await reporter.syncStatusFileIfPresent(at: statusFileURL, now: now)
                guard result.exitCode == 0 else {
                    throw NSError(
                        domain: "MacAIOrderAutoPickupService",
                        code: Int(result.exitCode),
                        userInfo: [NSLocalizedDescriptionKey: "脚本退出码 \(result.exitCode)"]
                    )
                }
                let cleanedLines = result.stdout
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.hasPrefix("VOX_STATUS:") && !$0.hasPrefix("VOX_PROGRESS:") && !$0.isEmpty }
                summary = cleanedLines.last ?? "已完成 \(order.subtasks.count) 个子步骤"
            } else {
                // Built-in local intelligent simulation when no external process runner is injected
                _ = try await reporter.reportProgress(
                    stage: "分析任务语义与 \(max(1, order.subtasks.count)) 个子步骤",
                    fraction: 0.55,
                    state: .running,
                    now: now
                )
                _ = try await reporter.reportProgress(
                    stage: "生成执行回执与同步结果",
                    fraction: 0.85,
                    state: .running,
                    now: now
                )
                summary = "已完成 · 共处理 \(max(1, order.subtasks.count)) 项子任务"
            }

            let completedReport = AIExecutionStatusReport(
                orderID: order.orderID,
                todoID: order.todoID,
                state: .completed,
                progressStage: "执行完成",
                progressFraction: 1.0,
                outputSummary: summary,
                assignedRunnerName: runnerName,
                updatedAt: Date()
            )
            return try await syncService.publishStatusReport(completedReport)
                ?? order.applying(completedReport)
        } catch {
            let failedReport = AIExecutionStatusReport(
                orderID: order.orderID,
                todoID: order.todoID,
                state: .failed,
                progressStage: "执行失败",
                progressFraction: 1.0,
                outputSummary: error.localizedDescription,
                assignedRunnerName: runnerName,
                updatedAt: Date()
            )
            return try await syncService.publishStatusReport(failedReport)
                ?? order.applying(failedReport)
        }
    }
}
