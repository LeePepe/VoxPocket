import Foundation
import CoreModels

public struct WatchTranscribedCapture: Sendable, Equatable {
    public let rawTranscript: String
    public let refinedText: String
    public init(rawTranscript: String, refinedText: String = "") { self.rawTranscript = rawTranscript; self.refinedText = refinedText }
}

public protocol WatchAudioTranscribing: Sendable {
    func transcribe(fileURL: URL) async throws -> WatchTranscribedCapture
}

public protocol WatchIngestPersistence: Sendable {
    func pending() async throws -> [WatchCaptureMetadata]
    func savePending(_ metadata: WatchCaptureMetadata) async throws
    func removePending(captureID: UUID) async throws
    func completion(for captureID: UUID) async throws -> WatchCaptureReceipt?
    func saveCompletion(_ receipt: WatchCaptureReceipt) async throws
}

public struct WatchTodoResult: Sendable, Equatable {
    public let title: String
    public let todoID: UUID
    public init(title: String, todoID: UUID) { self.title = title; self.todoID = todoID }
}

public typealias WatchTodoIngestion = @Sendable (_ captureID: UUID, _ transcript: WatchTranscribedCapture, _ metadata: WatchCaptureMetadata) async throws -> WatchTodoResult

public actor WatchCaptureIngestCoordinator {
    private let inboxDirectory: URL
    private var active: Set<UUID> = []
    private let persistence: any WatchIngestPersistence
    private let transcriber: any WatchAudioTranscribing
    private let ingestTodo: WatchTodoIngestion
    private let sendReceipt: @Sendable (WatchCaptureReceipt) async throws -> Void

    public init(inboxDirectory: URL, persistence: any WatchIngestPersistence, transcriber: any WatchAudioTranscribing, ingestTodo: @escaping WatchTodoIngestion, sendReceipt: @escaping @Sendable (WatchCaptureReceipt) async throws -> Void) {
        self.inboxDirectory = inboxDirectory
        self.persistence = persistence; self.transcriber = transcriber; self.ingestTodo = ingestTodo; self.sendReceipt = sendReceipt
    }

    public func enqueue(fileURL: URL, metadata: WatchCaptureMetadata) async throws {
        do {
            try validate(fileURL: fileURL, metadata: metadata)
            try await persistence.savePending(metadata)
        } catch {
            try? await sendReceipt(WatchCaptureReceipt(captureID: metadata.captureID, status: .failed(captureID: metadata.captureID, reason: "无法保存录音，请重试")))
            throw error
        }
        try await process(fileURL: fileURL, metadata: metadata)
    }

    public func resume(fileURLFor resolver: @Sendable (WatchCaptureMetadata) async -> URL?) async {
        guard let items = try? await persistence.pending() else { return }
        for metadata in items {
            guard !Task.isCancelled else { return }
            guard let url = await resolver(metadata) else { continue }
            try? await process(fileURL: url, metadata: metadata)
        }
    }

    private func process(fileURL: URL, metadata: WatchCaptureMetadata) async throws {
        guard active.insert(metadata.captureID).inserted else { return }
        defer { active.remove(metadata.captureID) }
        try Task.checkCancellation()
        if let completion = try await persistence.completion(for: metadata.captureID) {
            try? await sendReceipt(completion)
            try? await persistence.removePending(captureID: metadata.captureID)
            return
        }
        try validate(fileURL: fileURL, metadata: metadata)
        try? await sendReceipt(WatchCaptureReceipt(captureID: metadata.captureID, status: .processingOnPhone))
        do {
            let transcript = try await transcriber.transcribe(fileURL: fileURL)
            try Task.checkCancellation()
            guard !transcript.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !transcript.refinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WatchCaptureError.captureFailed
            }
            let todo = try await ingestTodo(metadata.captureID, transcript, metadata)
            let completion = WatchCaptureReceipt(captureID: metadata.captureID, status: .todoAdded(captureID: metadata.captureID, title: todo.title, todoID: todo.todoID))
            try await persistence.saveCompletion(completion)
            try? await sendReceipt(completion)
            try await persistence.removePending(captureID: metadata.captureID)
        } catch {
            if (try? await persistence.completion(for: metadata.captureID)) != nil { throw error }
            let failure = WatchCaptureReceipt(captureID: metadata.captureID, status: .failed(captureID: metadata.captureID, reason: "无法完成同步，请重试"))
            try? await sendReceipt(failure)
            throw error
        }
    }

    private func validate(fileURL: URL, metadata: WatchCaptureMetadata) throws {
        let root = inboxDirectory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard fileURL.lastPathComponent == metadata.basename, fileURL.standardizedFileURL.path.hasPrefix(root) else { throw WatchCaptureError.invalidAudioFile }
        try WatchAudioFileValidation.validate(fileURL)
    }
}

public actor InMemoryWatchIngestPersistence: WatchIngestPersistence {
    private var queue: [UUID: WatchCaptureMetadata] = [:]
    private var completions: [UUID: WatchCaptureReceipt] = [:]
    public init() {}
    public func pending() async throws -> [WatchCaptureMetadata] { Array(queue.values) }
    public func savePending(_ metadata: WatchCaptureMetadata) async throws { queue[metadata.captureID] = metadata }
    public func removePending(captureID: UUID) async throws { queue.removeValue(forKey: captureID) }
    public func completion(for captureID: UUID) async throws -> WatchCaptureReceipt? { completions[captureID] }
    public func saveCompletion(_ receipt: WatchCaptureReceipt) async throws { completions[receipt.captureID] = receipt }
}
