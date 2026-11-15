import Foundation
import SwiftUI
import Combine
import VoxPocketKit

@MainActor
final class WatchRecorderViewModel: ObservableObject {
    enum State: Equatable { case idle, starting, recording, stopping, transferring, processing, success(String), failed(String) }
    @Published private(set) var state: State = .idle
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var levels = Array(repeating: Float(0), count: 7)
    @Published private(set) var lastReceipt: WatchCaptureReceipt?
    @Published private(set) var queuedOffline = false
    private let recorder: any WatchAudioCapturing
    private let bridge: VoxWatchSyncBridge
    private var activeID: UUID?
    private var latestSubmittedID: UUID?
    private var retained: [UUID: WatchAudioCapture] = [:]
    private var receipts: [UUID: WatchCaptureReceipt] = [:]
    private var meterTask: Task<Void, Never>?
    private var receiptTask: Task<Void, Never>?

    init(recorder: any WatchAudioCapturing, bridge: VoxWatchSyncBridge) {
        self.recorder = recorder; self.bridge = bridge
        receiptTask = Task { [weak self, bridge] in
            let captures = (try? await bridge.retainedCaptures()) ?? []
            let savedReceipts = (try? await bridge.savedReceipts()) ?? []
            self?.restore(captures, savedReceipts: savedReceipts)
            for await receipt in await bridge.receiveReceipts() {
                guard !Task.isCancelled else { break }
                self?.apply(receipt)
            }
        }
    }
    var actionLocked: Bool { state == .starting || state == .stopping }
    var canRetry: Bool { retryableCapture != nil && !actionLocked && state != .recording }
    private var retryableCapture: WatchAudioCapture? {
        if let id = latestSubmittedID, let capture = retained[id] {
            if let receipt = receipts[id] {
                if case .failed = receipt.status { return capture }
            } else if case .failed = state {
                return capture
            }
        }
        return retained.values
            .filter { capture in
                guard let receipt = receipts[capture.captureID] else { return false }
                if case .failed = receipt.status { return true }
                return false
            }
            .last
    }
    func toggle() { if state == .recording { stop() } else { start() } }

    @discardableResult
    func start() -> Task<Void, Never>? {
        guard !actionLocked, state != .recording else { return nil }
        let id = UUID(); activeID = id; state = .starting; duration = 0; resetLevels()
        return Task { [weak self, recorder] in
            do {
                try await recorder.start(captureID: id)
                guard let self, activeID == id else { await recorder.cancel(); return }
                state = .recording
                meterTask = Task { [weak self, recorder] in
                    do {
                        for try await level in await recorder.levels(for: id) {
                            guard !Task.isCancelled else { return }
                            self?.sample(level)
                        }
                        if self?.state == .recording { self?.stop() }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self?.recordingFailed()
                    }
                }
            } catch {
                guard self?.activeID == id else { return }
                self?.activeID = nil; self?.state = .failed("无法开始录音，请检查麦克风权限")
            }
        }
    }
    @discardableResult
    func stop() -> Task<Void, Never>? {
        guard state == .recording else { return nil }
        state = .stopping; meterTask?.cancel(); meterTask = nil; resetLevels()
        return Task { [weak self, recorder] in
            do {
                let capture = try await recorder.stop()
                guard let self else { return }
                activeID = nil; duration = capture.duration
                retained[capture.captureID] = capture; latestSubmittedID = capture.captureID
                await submit(capture)
            } catch { self?.recordingFailed() }
        }
    }
    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard canRetry, let capture = retryableCapture else { return nil }
        latestSubmittedID = capture.captureID
        state = .transferring
        return Task { [weak self] in guard let self else { return }; await submit(capture) }
    }
    private func submit(_ capture: WatchAudioCapture) async {
        state = .transferring
        queuedOffline = !(await bridge.isReachable)
        let transferring = WatchCaptureReceipt(captureID: capture.captureID, status: .transferring)
        receipts[capture.captureID] = transferring; lastReceipt = transferring
        do { apply(try await bridge.send(capture: capture)) }
        catch { apply(WatchCaptureReceipt(captureID: capture.captureID, status: .failed(captureID: capture.captureID, reason: "未能同步，请重试"))) }
    }
    func apply(_ receipt: WatchCaptureReceipt) {
        guard receipt.isValid, retained[receipt.captureID] != nil || receipts[receipt.captureID] != nil else { return }
        if let previous = receipts[receipt.captureID], !receipt.canFollow(previous) { return }
        receipts[receipt.captureID] = receipt
        if case .todoAdded = receipt.status { retained.removeValue(forKey: receipt.captureID) }
        guard latestSubmittedID == receipt.captureID else { return }
        lastReceipt = receipt
        guard activeID == nil, !actionLocked else { return }
        switch receipt.status {
        case .transferring: state = .transferring
        case .processingOnPhone: state = .processing
        case .todoAdded(_, let title, _): state = .success(title)
        case .failed: state = .failed("未能同步，请在 iPhone 打开 VoxPocket 后重试")
        }
    }
    private func restore(_ captures: [WatchAudioCapture], savedReceipts: [WatchCaptureReceipt]) {
        for capture in captures { retained[capture.captureID] = capture }
        for receipt in savedReceipts where receipts[receipt.captureID] == nil { receipts[receipt.captureID] = receipt }
        if latestSubmittedID == nil {
            let failedRetainedReceipt = savedReceipts.last { receipt in
                guard retained[receipt.captureID] != nil else { return false }
                if case .failed = receipt.status { return true }
                return false
            }
            let selected = failedRetainedReceipt ?? savedReceipts.last
            latestSubmittedID = selected?.captureID ?? captures.last?.captureID
            if let selected { apply(selected) }
        }
    }
    private func sample(_ level: WatchAudioLevel) {
        guard activeID == level.captureID, state == .recording else { return }
        duration = max(duration, level.elapsed)
        levels = Array(levels.dropFirst()) + [level.normalizedLevel]
    }
    private func recordingFailed() { activeID = nil; resetLevels(); state = .failed("无法完成录音，请重试") }
    private func resetLevels() { levels = Array(repeating: 0, count: 7) }
    deinit { meterTask?.cancel(); receiptTask?.cancel() }
}
