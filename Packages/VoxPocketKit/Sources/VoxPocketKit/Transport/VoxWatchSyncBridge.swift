import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

public actor VoxWatchSyncBridge {
    private struct Item: Codable {
        let metadata: WatchCaptureMetadata
        var receipt: WatchCaptureReceipt
        var enqueuedAt: Date?
        let createdAt: Date
    }
    private let transport: any WatchSyncTransport
    private let storageDirectory: URL
    private var items: [UUID: Item] = [:]
    private var loaded = false
    private var inFlight: Set<UUID> = []
    private var retryRequested: Set<UUID> = []
    private var flushing = false
    private var observing = false
    private var receiptTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<WatchCaptureReceipt>.Continuation] = [:]
    private let replayInterval: TimeInterval

    public init(transport: any WatchSyncTransport, storageDirectory: URL, replayInterval: TimeInterval = 300) {
        self.transport = transport; self.storageDirectory = storageDirectory; self.replayInterval = replayInterval
    }

    public func activate() async throws {
        try load()
        await observe()
        await transport.activate()
        inFlight = await transport.outstandingCaptureIDs()
        await flushPending()
    }

    public func send(capture: WatchAudioCapture) async throws -> WatchCaptureReceipt {
        try load(excluding: capture.captureID); await observe()
        let metadata = try WatchCaptureMetadata(captureID: capture.captureID, duration: capture.duration, basename: capture.fileURL.lastPathComponent)
        let url = storageDirectory.appendingPathComponent(metadata.basename)
        if let old = items[capture.captureID], case .todoAdded = old.receipt.status { return old.receipt }
        try WatchAudioFileValidation.validate(capture.fileURL)
        if let old = items[capture.captureID], old.metadata != metadata { throw WatchCaptureError.invalidAudioFile }
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let recovery = storageDirectory.appendingPathComponent("\(capture.captureID.uuidString).capture.json")
        try JSONEncoder().encode(metadata).write(to: recovery, options: .atomic)
        if capture.fileURL.standardizedFileURL != url.standardizedFileURL, !FileManager.default.fileExists(atPath: url.path) {
            let partial = storageDirectory.appendingPathComponent("\(UUID().uuidString).part")
            defer { try? FileManager.default.removeItem(at: partial) }
            try FileManager.default.copyItem(at: capture.fileURL, to: partial)
            try FileManager.default.moveItem(at: partial, to: url)
        }
        if let old = items[capture.captureID] {
            guard old.metadata == metadata else { throw WatchCaptureError.invalidAudioFile }
            if case .todoAdded = old.receipt.status { return old.receipt }
            if case .failed = old.receipt.status {
                retryRequested.insert(capture.captureID)
                items[capture.captureID]?.receipt = WatchCaptureReceipt(captureID: capture.captureID, status: .transferring)
                items[capture.captureID]?.enqueuedAt = nil
            }
        } else {
            items[capture.captureID] = Item(metadata: metadata, receipt: WatchCaptureReceipt(captureID: capture.captureID, status: .transferring), createdAt: Date())
        }
        try persist()
        try? FileManager.default.removeItem(at: recovery)
        await flushPending()
        return items[capture.captureID]!.receipt
    }

    public var isReachable: Bool { get async { await transport.isReachable } }
    public func retainedCaptures() throws -> [WatchAudioCapture] {
        try load()
        return items.values.sorted(by: { $0.createdAt < $1.createdAt }).compactMap { item in
            if case .todoAdded = item.receipt.status { return nil }
            let url = storageDirectory.appendingPathComponent(item.metadata.basename)
            guard (try? WatchAudioFileValidation.validate(url)) != nil else { return nil }
            return WatchAudioCapture(captureID: item.metadata.captureID, fileURL: url, duration: item.metadata.duration)
        }
    }
    public func latestReceipt(for captureID: UUID) -> WatchCaptureReceipt? { items[captureID]?.receipt }
    public func savedReceipts() throws -> [WatchCaptureReceipt] {
        try load(); return items.values.sorted(by: { $0.createdAt < $1.createdAt }).map(\.receipt)
    }

    public func receiveReceipts() async -> AsyncStream<WatchCaptureReceipt> {
        try? load(); await observe()
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: WatchCaptureReceipt.self)
        subscribers[id] = continuation
        for item in items.values { continuation.yield(item.receipt) }
        continuation.onTermination = { [weak self] _ in Task { await self?.removeSubscriber(id) } }
        return stream
    }
    private func removeSubscriber(_ id: UUID) { subscribers.removeValue(forKey: id) }

    private func observe() async {
        guard !observing else { return }
        observing = true
        let receipts = await transport.receipts()
        let events = await transport.events()
        receiptTask = Task { [weak self] in for await receipt in receipts { await self?.accept(receipt) } }
        eventTask = Task { [weak self] in for await event in events { await self?.handle(event) } }
    }
    private func accept(_ receipt: WatchCaptureReceipt) {
        guard receipt.isValid, var item = items[receipt.captureID], receipt != item.receipt, receipt.canFollow(item.receipt) else { return }
        let old = item
        item.receipt = receipt; items[receipt.captureID] = item
        do { try persist() } catch { items[receipt.captureID] = old; return }
        if case .todoAdded = receipt.status {
            inFlight.remove(receipt.captureID)
            try? FileManager.default.removeItem(at: storageDirectory.appendingPathComponent(item.metadata.basename))
        }
        for continuation in subscribers.values { continuation.yield(receipt) }
    }
    private func handle(_ event: WatchTransportEvent) async {
        switch event {
        case .activated, .reachabilityChanged: await flushPending()
        case .fileFinished(let id, let succeeded):
            inFlight.remove(id)
            let retry = retryRequested.remove(id) != nil
            if !succeeded && !retry {
                items[id]?.enqueuedAt = nil
                if let item = items[id], case .transferring = item.receipt.status {
                    accept(WatchCaptureReceipt(captureID: id, status: .failed(captureID: id, reason: "未能同步，请重试")))
                }
                try? persist()
            }
            await flushPending()
        }
    }
    private func flushPending() async {
        guard !flushing, await transport.canQueueFiles else { return }
        flushing = true; defer { flushing = false }
        inFlight.formUnion(await transport.outstandingCaptureIDs())
        for id in items.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let item = items[id], !inFlight.contains(id) else { continue }
            if case .todoAdded = item.receipt.status { continue }
            if case .failed = item.receipt.status { continue }
            if let date = item.enqueuedAt, Date().timeIntervalSince(date) < replayInterval { continue }
            inFlight.insert(id)
            do {
                try await transport.transferFile(storageDirectory.appendingPathComponent(item.metadata.basename), metadata: item.metadata)
                items[id]?.enqueuedAt = Date(); try persist()
            } catch {
                inFlight.remove(id)
                accept(WatchCaptureReceipt(captureID: id, status: .failed(captureID: id, reason: "未能同步，请重试")))
            }
        }
    }
    private func load(excluding: UUID? = nil) throws {
        guard !loaded else { return }
        let url = storageDirectory.appendingPathComponent("sender.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try JSONDecoder().decode([Item].self, from: Data(contentsOf: url))
            items = Dictionary(values.map { ($0.metadata.captureID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        if FileManager.default.fileExists(atPath: storageDirectory.path) {
            let files = try FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
                .sorted { $0.pathExtension == "json" && $1.pathExtension != "json" }
            for file in files {
                if file.lastPathComponent.hasSuffix(".capture.json"),
                   (try? WatchAudioFileValidation.validateRegularFile(file, maxBytes: 4096)) != nil,
                   let metadata = try? JSONDecoder().decode(WatchCaptureMetadata.self, from: Data(contentsOf: file)),
                   metadata.captureID != excluding, file.lastPathComponent == "\(metadata.captureID.uuidString).capture.json",
                   items[metadata.captureID] == nil {
                    items[metadata.captureID] = Item(metadata: metadata, receipt: WatchCaptureReceipt(captureID: metadata.captureID, status: .transferring), createdAt: Date())
                }
                #if canImport(AVFoundation)
                if file.pathExtension == "m4a", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                   id != excluding, items[id] == nil, (try? WatchAudioFileValidation.validate(file)) != nil,
                   let audio = try? AVAudioPlayer(contentsOf: file),
                   let metadata = try? WatchCaptureMetadata(captureID: id, duration: audio.duration, basename: file.lastPathComponent) {
                    items[id] = Item(metadata: metadata, receipt: WatchCaptureReceipt(captureID: id, status: .transferring), createdAt: Date())
                }
                #endif
            }
            try persist()
        }
        loaded = true
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(items.values)).write(to: storageDirectory.appendingPathComponent("sender.json"), options: .atomic)
    }
    deinit { receiptTask?.cancel(); eventTask?.cancel() }
}

public extension WatchCaptureReceipt {
    var isValid: Bool {
        switch status {
        case .todoAdded(let id, let title, _): id == captureID && !title.isEmpty && title.utf8.count <= 16_384
        case .failed(let id, let reason): id == captureID && !reason.isEmpty && reason.utf8.count <= 1024
        default: true
        }
    }
    func canFollow(_ previous: WatchCaptureReceipt) -> Bool {
        guard captureID == previous.captureID, isValid else { return false }
        if case .todoAdded = previous.status { return self == previous }
        if case .processingOnPhone = previous.status, case .transferring = status { return false }
        if case .failed = previous.status {
            if case .todoAdded = status { return true }
            return false
        }
        return true
    }
}
