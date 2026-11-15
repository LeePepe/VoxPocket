#if os(iOS)
import Foundation
import VoxPocketKit

actor WatchReceiverBox {
    private let inbox: WatchInboxStore
    private var files: [UUID: (URL, WatchCaptureMetadata)] = [:]
    private var notify: (@Sendable () async -> Void)?
    init(inbox: WatchInboxStore) { self.inbox = inbox }
    func setReady(notify: @escaping @Sendable () async -> Void) async {
        self.notify = notify
        await recover()
        await notify()
    }
    func receive(url: URL, metadata: WatchCaptureMetadata) async {
        files[metadata.captureID] = (url, metadata)
        await notify?()
    }
    func recover() async {
        guard let recovered = try? inbox.recover() else { return }
        for (url, metadata) in recovered { files[metadata.captureID] = (url, metadata) }
    }
    func remove(_ ids: Set<UUID>) { for id in ids { files.removeValue(forKey: id) } }
    var hasFiles: Bool { !files.isEmpty }
    func next() -> (URL, WatchCaptureMetadata)? {
        guard let id = files.keys.sorted(by: { $0.uuidString < $1.uuidString }).first else { return nil }
        return files.removeValue(forKey: id)
    }
}
#endif
