#if os(iOS)
import Foundation
import UIKit
import VoxPocketKit
import CoreModels
import UseCases
import Persistence
import VoxKitBridge

@MainActor
final class WatchCaptureAppAssembly {
    private let transport: WCSessionTransport
    private let coordinator: WatchCaptureIngestCoordinator
    private let receiver: WatchReceiverBox
    private let inboxURL: URL
    private let persistence: FileWatchIngestPersistence
    private var ready = false
    private var work: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    init(useCase: DefaultVoiceCaptureAndTodoUseCase, captureRepository: DefaultVoiceCaptureRepository,
         storageDirectory: URL, makeRefinement: @escaping @Sendable () -> any RefineWorkflowRunning, refresh: @escaping @MainActor @Sendable () -> Void) {
        let inboxURL = storageDirectory.appendingPathComponent("WatchInbox", isDirectory: true)
        self.inboxURL = inboxURL
        let persistence = FileWatchIngestPersistence(directory: inboxURL.appendingPathComponent("state"))
        self.persistence = persistence
        let receiver = WatchReceiverBox(inbox: WatchInboxStore(directory: inboxURL))
        self.receiver = receiver
        let transport = WCSessionTransport(inboxDirectory: inboxURL) { url, metadata in await receiver.receive(url: url, metadata: metadata) }
        self.transport = transport
        let adapter = WatchTodoIngestAdapter(useCase: useCase)
        coordinator = WatchCaptureIngestCoordinator(inboxDirectory: inboxURL,
            persistence: persistence,
            transcriber: SpeechURLWatchTranscriber(makeRefinement: makeRefinement),
            ingestTodo: { id, transcript, metadata in
                let result = try await adapter.ingest(captureID: id, transcript: transcript, metadata: metadata)
                await refresh()
                return result
            }, sendReceipt: { try await transport.transferReceipt($0) })
    }

    func start(prepare: @escaping @MainActor () async -> Bool) {
        Task {
            // 仅文件领取提前启动；此 task 在 ServiceContainer 构造返回后才进入 readiness。
            await transport.activate()
            guard await prepare() else { return }
            ready = true
            foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.resume() }
            }
            await receiver.setReady { [weak self] in await self?.schedule() }
        }
    }
    private func resume() async {
        guard ready else { return }
        if work?.isCancelled == true { await work?.value }
        await receiver.recover(); schedule()
    }
    private func schedule() {
        guard ready, work == nil else { return }
        work = Task { [weak self, receiver, coordinator] in
            guard let self else { return }
            var identifier: UIBackgroundTaskIdentifier = .invalid
            identifier = UIApplication.shared.beginBackgroundTask(withName: "Watch capture ingestion") { [weak self] in self?.work?.cancel() }
            let limit = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(25))
                    if UIApplication.shared.applicationState != .active { self?.work?.cancel() }
                } catch {}
            }
            defer {
                limit.cancel()
                if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
                let cancelled = Task.isCancelled
                work = nil
                if !cancelled {
                    Task { [weak self] in if await receiver.hasFiles { self?.schedule() } }
                }
            }
            let pending = (try? await persistence.pending()) ?? []
            await receiver.remove(Set(pending.map(\.captureID)))
            await coordinator.resume { [inboxURL] metadata in
                inboxURL.appendingPathComponent(metadata.captureID.uuidString).appendingPathComponent(metadata.basename)
            }
            while !Task.isCancelled, let (url, metadata) = await receiver.next() {
                do { try await coordinator.enqueue(fileURL: url, metadata: metadata) } catch {}
            }
        }
    }
}
#endif
