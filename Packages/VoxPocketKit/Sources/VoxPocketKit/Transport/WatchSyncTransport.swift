import Foundation

public enum WatchTransportEvent: Sendable {
    case activated, reachabilityChanged
    case fileFinished(UUID, succeeded: Bool)
}

public protocol WatchSyncTransport: Sendable {
    var isReachable: Bool { get async }
    var canQueueFiles: Bool { get async }
    func activate() async
    func outstandingCaptureIDs() async -> Set<UUID>
    func transferFile(_ url: URL, metadata: WatchCaptureMetadata) async throws
    func transferReceipt(_ receipt: WatchCaptureReceipt) async throws
    func receipts() async -> AsyncStream<WatchCaptureReceipt>
    func events() async -> AsyncStream<WatchTransportEvent>
}

public extension WatchSyncTransport {
    var canQueueFiles: Bool { get async { await isReachable } }
    func outstandingCaptureIDs() async -> Set<UUID> { [] }
    func events() async -> AsyncStream<WatchTransportEvent> { AsyncStream { $0.finish() } }
}

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import WatchConnectivity

// Sendable: WCSession 系统回调只使用不可变依赖、线程安全 continuation 与 inbox Mutex；没有 UI 或裸可变状态。
public final class WCSessionTransport: NSObject, WatchSyncTransport, WCSessionDelegate, @unchecked Sendable {
    private let inbox: WatchInboxStore
    private let onFileReceived: (@Sendable (URL, WatchCaptureMetadata) async -> Void)?
    private let receiptStream: AsyncStream<WatchCaptureReceipt>
    private let receiptContinuation: AsyncStream<WatchCaptureReceipt>.Continuation
    private let eventStream: AsyncStream<WatchTransportEvent>
    private let eventContinuation: AsyncStream<WatchTransportEvent>.Continuation

    public init(inboxDirectory: URL, onFileReceived: (@Sendable (URL, WatchCaptureMetadata) async -> Void)? = nil) {
        self.inbox = WatchInboxStore(directory: inboxDirectory)
        self.onFileReceived = onFileReceived
        (receiptStream, receiptContinuation) = AsyncStream.makeStream(of: WatchCaptureReceipt.self)
        (eventStream, eventContinuation) = AsyncStream.makeStream(of: WatchTransportEvent.self)
        super.init()
    }
    public var isReachable: Bool { get async { WCSession.default.isReachable } }
    public var canQueueFiles: Bool { get async { WCSession.default.activationState == .activated } }
    public func activate() async { WCSession.default.delegate = self; WCSession.default.activate() }
    public func outstandingCaptureIDs() async -> Set<UUID> {
        Set(WCSession.default.outstandingFileTransfers.compactMap { Self.metadata($0.file.metadata)?.captureID })
    }
    public func transferFile(_ url: URL, metadata: WatchCaptureMetadata) async throws {
        try WatchAudioFileValidation.validate(url)
        guard await canQueueFiles else { throw WatchCaptureError.transportUnavailable }
        guard !(await outstandingCaptureIDs()).contains(metadata.captureID) else { return }
        WCSession.default.transferFile(url, metadata: ["captureMetadata": try JSONEncoder().encode(metadata)])
    }
    public func transferReceipt(_ receipt: WatchCaptureReceipt) async throws {
        let data = try JSONEncoder().encode(receipt)
        WCSession.default.transferUserInfo(["receipt": data])
        if WCSession.default.isReachable {
            WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: { _ in })
        }
    }
    public func receipts() async -> AsyncStream<WatchCaptureReceipt> { receiptStream }
    public func events() async -> AsyncStream<WatchTransportEvent> { eventStream }
    private static func metadata(_ value: [String: Any]?) -> WatchCaptureMetadata? {
        guard let data = value?["captureMetadata"] as? Data, data.count <= 4096 else { return nil }
        return try? JSONDecoder().decode(WatchCaptureMetadata.self, from: data)
    }
    // Sendable: WCSession invokes this system callback off-main; the copied URL and Codable metadata are immutable before crossing the task boundary.
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = Self.metadata(file.metadata) else { return }
        do {
            let destination = try inbox.claim(file.fileURL, metadata: metadata)
            if let onFileReceived { Task { await onFileReceived(destination, metadata) } }
        } catch {
            Task { try? await transferReceipt(WatchCaptureReceipt(captureID: metadata.captureID, status: .failed(captureID: metadata.captureID, reason: "无法保存录音，请重试"))) }
        }
    }
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        guard let data = userInfo["receipt"] as? Data else { return }
        receiveReceipt(data)
    }
    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) { receiveReceipt(messageData) }
    public func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        receiveReceipt(messageData); replyHandler(Data())
    }
    private func receiveReceipt(_ data: Data) {
        guard data.count <= 64 * 1024, let receipt = try? JSONDecoder().decode(WatchCaptureReceipt.self, from: data), receipt.isValid else { return }
        receiptContinuation.yield(receipt)
    }
    public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated { eventContinuation.yield(.activated) }
    }
    public func sessionReachabilityDidChange(_ session: WCSession) { eventContinuation.yield(.reachabilityChanged) }
    public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let metadata = Self.metadata(fileTransfer.file.metadata) else { return }
        eventContinuation.yield(.fileFinished(metadata.captureID, succeeded: error == nil))
    }
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
