#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI
import VoxPocketKit

/// 仅模拟器 Debug 的启动参数测试缝；渲染真实生产 View，不提供任何屏内状态控件。
@MainActor
enum WatchSnapshotHarness {
    static var state: String? { ProcessInfo.processInfo.environment["VOX_WATCH_SNAPSHOT"] }
    static var appearance: ColorScheme? { ProcessInfo.processInfo.environment["VOX_WATCH_APPEARANCE"] == "light" ? .light : .dark }
    static var reducedEffects: Bool { ProcessInfo.processInfo.environment["VOX_WATCH_REDUCED_EFFECTS"] == "1" }
    static func makeModel(storage: URL) -> WatchRecorderViewModel {
        let folder = storage.appendingPathComponent("Snapshot/\(UUID().uuidString)")
        return WatchRecorderViewModel(recorder: SnapshotRecorder(folder: folder), bridge: VoxWatchSyncBridge(transport: SnapshotTransport(), storageDirectory: folder))
    }
    static func apply(to model: WatchRecorderViewModel) async {
        guard let state, state != "idle" else { return }
        await model.start()?.value
        if state == "recording" { return }
        await model.stop()?.value
        guard let id = model.lastReceipt?.captureID else { return }
        switch state {
        case "processing": model.apply(WatchCaptureReceipt(captureID: id, status: .processingOnPhone))
        case "success", "long-title":
            let title = state == "long-title" ? "整理周一产品评审会议纪要并确认下周需要完成的三项改进工作" : "整理会议纪要"
            model.apply(WatchCaptureReceipt(captureID: id, status: .todoAdded(captureID: id, title: title, todoID: UUID())))
        case "failed": model.apply(WatchCaptureReceipt(captureID: id, status: .failed(captureID: id, reason: "请在 iPhone 打开 VoxPocket 后重试")))
        default: break
        }
    }
}
private actor SnapshotRecorder: WatchAudioCapturing {
    let folder: URL
    var id: UUID?
    var continuation: AsyncThrowingStream<WatchAudioLevel, Error>.Continuation?
    init(folder: URL) { self.folder = folder }
    func start(captureID: UUID) throws {
        id = captureID
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32).write(to: folder.appendingPathComponent("\(captureID.uuidString).m4a"))
    }
    func stop() throws -> WatchAudioCapture {
        guard let id else { throw WatchCaptureError.notRecording }
        self.id = nil; continuation?.finish()
        return WatchAudioCapture(captureID: id, fileURL: folder.appendingPathComponent("\(id.uuidString).m4a"), duration: 15)
    }
    func cancel() { id = nil; continuation?.finish() }
    func levels(for captureID: UUID) -> AsyncThrowingStream<WatchAudioLevel, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            for value: Float in [0.05, 0.3, 0.55, 0.9, 0.7, 0.25, 0.1] {
                continuation.yield(WatchAudioLevel(captureID: captureID, normalizedLevel: value, elapsed: 15))
            }
        }
    }
}
private actor SnapshotTransport: WatchSyncTransport {
    var isReachable: Bool { get async { false } }
    func activate() async {}
    func transferFile(_ url: URL, metadata: WatchCaptureMetadata) async throws { throw WatchCaptureError.transportUnavailable }
    func transferReceipt(_ receipt: WatchCaptureReceipt) async throws {}
    func receipts() async -> AsyncStream<WatchCaptureReceipt> { AsyncStream { $0.finish() } }
}
#endif
