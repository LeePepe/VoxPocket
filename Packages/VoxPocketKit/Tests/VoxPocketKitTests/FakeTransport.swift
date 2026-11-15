import Foundation
@testable import VoxPocketKit

actor FakeTransport: WatchSyncTransport {
    var reachable = false
    var transfers: [UUID] = []
    var outstanding: Set<UUID> = []
    var onFile: (@Sendable (URL, WatchCaptureMetadata) async throws -> Void)?
    private let receiptPair = AsyncStream<WatchCaptureReceipt>.makeStream()
    private let eventPair = AsyncStream<WatchTransportEvent>.makeStream()
    var isReachable: Bool { get async { reachable } }
    func setReachable(_ value: Bool) { reachable = value; eventPair.continuation.yield(.reachabilityChanged) }
    func setOnFile(_ action: @escaping @Sendable (URL, WatchCaptureMetadata) async throws -> Void) { onFile = action }
    func activate() async {}
    func outstandingCaptureIDs() async -> Set<UUID> { outstanding }
    func transferFile(_ url: URL, metadata: WatchCaptureMetadata) async throws {
        transfers.append(metadata.captureID); outstanding.insert(metadata.captureID)
        try await onFile?(url, metadata)
    }
    func finishFile(_ id: UUID, succeeded: Bool) {
        outstanding.remove(id); eventPair.continuation.yield(.fileFinished(id, succeeded: succeeded))
    }
    func transferReceipt(_ receipt: WatchCaptureReceipt) async throws { receiptPair.continuation.yield(receipt) }
    func receipts() async -> AsyncStream<WatchCaptureReceipt> { receiptPair.stream }
    func events() async -> AsyncStream<WatchTransportEvent> { eventPair.stream }
}
