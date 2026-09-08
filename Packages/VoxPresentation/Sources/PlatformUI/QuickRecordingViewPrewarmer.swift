#if os(macOS)
import AppKit
import SwiftUI

/// 只预热空视图，不持有 ViewModel、录音服务或用户文本。
@MainActor
public final class QuickRecordingViewPrewarmer {
    public private(set) var isPrepared = false
    private var pendingTask: Task<Void, Never>?
    var isScheduled: Bool { pendingTask != nil }

    public init() {}

    public func schedule() {
        guard !isPrepared, pendingTask == nil else { return }
        pendingTask = Task(priority: .background) { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self else { return }
            self.prepare()
            self.pendingTask = nil
        }
    }

    public func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    func prepare() {
        guard !isPrepared else { return }
        let size = CGSize(width: QuickRecordingLayout.panelWidth, height: QuickRecordingLayout.panelHeight)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.contentView = nil; panel.close() }
        let host = NSHostingView(rootView: QuickRecordingIslandView(status: .listening, transcript: "",
                                                                   forceReducedMotion: true))
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        // 从未 orderFront，不显示窗口、不抢焦点；位图仅在内存中帮助初始化绘制资源。
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        isPrepared = true
    }
}
#endif
