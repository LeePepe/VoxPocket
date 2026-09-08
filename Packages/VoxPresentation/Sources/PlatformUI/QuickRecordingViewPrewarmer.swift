#if os(macOS)
import AppKit
import SwiftUI

/// 只预热空视图，不持有 ViewModel、录音服务或用户文本。
@MainActor
public final class QuickRecordingViewPrewarmer {
    public private(set) var isPrepared = false
    private var pendingTask: Task<Void, Never>?
    private var generation = 0
    var isScheduled: Bool { pendingTask != nil }

    public init() {}

    public func schedule() {
        guard !isPrepared, pendingTask == nil else { return }
        generation += 1
        let scheduledGeneration = generation
        pendingTask = Task(priority: .background) { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self else { return }
            do { try await self.prepare() } catch { /* 用户优先：取消后不继续准备。 */ }
            if self.generation == scheduledGeneration { self.pendingTask = nil }
        }
    }

    public func cancelPending() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
    }

    func prepare() async throws {
        guard !isPrepared else { return }
        try Task.checkCancellation()
        let host = NSHostingView(rootView: QuickRecordingIslandView(status: .listening, transcript: "",
                                                                   forceReducedMotion: true))
        // AppKit 必须在主 actor；分段让出执行权。低优先级只影响调度，不会把 UI 移到后台。
        try await Task.sleep(for: .milliseconds(16))
        let size = CGSize(width: QuickRecordingLayout.panelWidth, height: QuickRecordingLayout.panelHeight)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.contentView = nil; panel.close() }
        try await Task.sleep(for: .milliseconds(16))
        panel.contentView = host
        // 只构造视图树，让系统自然处理布局；不强制布局、显示或生成位图。
        try await Task.sleep(for: .milliseconds(16))
        isPrepared = true
    }
}
#endif
