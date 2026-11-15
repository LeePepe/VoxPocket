import SwiftUI
import VoxPocketKit

@main
struct VoxPocketWatchApp: App {
    @StateObject private var model: WatchRecorderViewModel

    init() {
        let storage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoxPocket", isDirectory: true)
        #if DEBUG && targetEnvironment(simulator)
        if WatchSnapshotHarness.state != nil {
            _model = StateObject(wrappedValue: WatchSnapshotHarness.makeModel(storage: storage))
            return
        }
        #endif
        let recorder = WatchAudioCaptureService(storageURL: storage)
        #if canImport(WatchConnectivity)
        let syncBridge = VoxWatchSyncBridge(transport: WCSessionTransport(inboxDirectory: storage.appendingPathComponent("WatchInbox", isDirectory: true)), storageDirectory: storage)
        #else
        let syncBridge = VoxWatchSyncBridge(transport: UnavailableWatchTransport(), storageDirectory: storage)
        #endif
        let model = WatchRecorderViewModel(recorder: recorder, bridge: syncBridge)
        _model = StateObject(wrappedValue: model)
        WatchRecordingRuntime.install { model.start() }
        Task { try? await syncBridge.activate() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if WatchSnapshotHarness.state != nil {
                    WatchRecorderView(model: model, reducedEffects: WatchSnapshotHarness.reducedEffects)
                        .preferredColorScheme(WatchSnapshotHarness.appearance)
                        .environment(\.colorScheme, WatchSnapshotHarness.appearance ?? .dark)
                        .task { await WatchSnapshotHarness.apply(to: model) }
                } else {
                    WatchRecorderView(model: model)
                }
                #else
                WatchRecorderView(model: model)
                #endif
            }
            .onOpenURL { WatchRecordingRuntime.open($0) }
        }
    }
}

private struct UnavailableWatchTransport: WatchSyncTransport {
    var isReachable: Bool { get async { false } }
    func activate() async {}
    func transferFile(_ url: URL, metadata: WatchCaptureMetadata) async throws { throw WatchCaptureError.transportUnavailable }
    func transferReceipt(_ receipt: WatchCaptureReceipt) async throws { throw WatchCaptureError.transportUnavailable }
    func receipts() async -> AsyncStream<WatchCaptureReceipt> { AsyncStream { $0.finish() } }
}
