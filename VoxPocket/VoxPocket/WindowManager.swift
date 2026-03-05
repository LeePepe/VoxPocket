//
//  WindowManager.swift
//  VoxPocket
//
//  管理浮动窗口（NSPanel）的创建和显示
//

#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import Combine
import UIShared
import PlatformUI
import Observability

/// 窗口类型
public enum WindowType: String, CaseIterable {
    case fullPanel = "FullPanel"
    case quickRecording = "QuickRecording"
}

/// 窗口管理器
///
/// 管理 VoxPocket 的浮动窗口实例。
@MainActor
public final class WindowManager: ObservableObject {

    // MARK: - 单例

    public static let shared = WindowManager()

    // MARK: - 属性

    private var windows: [WindowType: NSPanel] = [:]
    private var windowControllers: [WindowType: NSWindowController] = [:]
    private var viewModels: [WindowType: Any] = [:]
    private let logger: Logger = PrintLogger(subsystem: "WindowManager")
    
    /// 窗口可见状态
    @Published public var windowVisibility: [WindowType: Bool] = [
        .fullPanel: false,
        .quickRecording: false
    ]

    // MARK: - 初始化

    private init() {}

    // MARK: - 窗口管理

    /// 显示窗口
    public func showWindow(_ type: WindowType) {
        if let existingWindow = windows[type] {
            positionWindow(existingWindow, for: type)
            existingWindow.makeKeyAndOrderFront(nil)
            windowVisibility[type] = true
            autoResumeIfNeeded(type)
            logger.log(.debug, "Showing existing window", context: ["type": type.rawValue])
            return
        }

        let panel = createPanel(for: type)
        windows[type] = panel

        let controller = NSWindowController(window: panel)
        windowControllers[type] = controller

        positionWindow(panel, for: type)
        panel.makeKeyAndOrderFront(nil)
        windowVisibility[type] = true
        autoResumeIfNeeded(type)

        logger.log(.debug, "Created and showing window", context: ["type": type.rawValue])
    }

    private func positionWindow(_ panel: NSPanel, for type: WindowType) {
        switch type {
        case .fullPanel:
            panel.center()
        case .quickRecording:
            positionQuickRecordingWindow(panel)
        }
    }

    private func positionQuickRecordingWindow(_ panel: NSPanel) {
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panel.frame.width / 2
        let y = max(visibleFrame.minY, visibleFrame.maxY - QuickRecordingLayout.topInset - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 面板唤起时自动开始录音
    private func autoResumeIfNeeded(_ type: WindowType) {
        guard type == .fullPanel else { return }
        guard let viewModel = viewModels[.fullPanel] as? RootViewModel<SessionListViewModel, EditorViewModel> else { return }
        guard !viewModel.editorState.isRecording else { return }
        Task {
            await viewModel.editorState.toggleRecording()
        }
    }

    /// 隐藏窗口
    public func hideWindow(_ type: WindowType) {
        guard let window = windows[type] else { return }
        window.orderOut(nil)
        windowVisibility[type] = false
        logger.log(.debug, "Hiding window", context: ["type": type.rawValue])
    }

    /// 切换窗口显示状态
    public func toggleWindow(_ type: WindowType) {
        if let window = windows[type], window.isVisible {
            hideWindow(type)
        } else {
            showWindow(type)
        }
    }

    /// 关闭并释放窗口
    public func closeWindow(_ type: WindowType) {
        guard let window = windows[type] else { return }
        window.close()
        windows.removeValue(forKey: type)
        windowControllers.removeValue(forKey: type)
        viewModels.removeValue(forKey: type)
        windowVisibility[type] = false
        logger.log(.debug, "Closed window", context: ["type": type.rawValue])
    }

    /// 获取窗口的 ViewModel
    public func getViewModel<T>(_ type: WindowType) -> T? {
        viewModels[type] as? T
    }

    /// 获取快速录音 ViewModel
    public func getQuickRecordingViewModel() -> QuickRecordingViewModel? {
        viewModels[.quickRecording] as? QuickRecordingViewModel
    }

    // MARK: - 窗口创建

    private func createPanel(for type: WindowType) -> NSPanel {
        switch type {
        case .fullPanel:
            return createFullPanel()
        case .quickRecording:
            return createQuickRecordingPanel()
        }
    }

    /// 创建完整面板窗口
    private func createFullPanel() -> NSPanel {
        let viewModel = ServiceContainer.shared.makeRootViewModel()
        viewModels[.fullPanel] = viewModel

        let contentView = FullPanelView(viewModel: viewModel)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear

        // 设置最小尺寸
        panel.minSize = NSSize(width: 460, height: 320)

        // 设置 SwiftUI 内容
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView

        // 窗口关闭时更新状态
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.windowVisibility[.fullPanel] = false
        }

        return panel
    }

    /// 创建快速录音窗口
    private func createQuickRecordingPanel() -> NSPanel {
        let viewModel = ServiceContainer.shared.makeQuickRecordingViewModel()
        viewModels[.quickRecording] = viewModel

        let contentView = QuickRecordingView(viewModel: viewModel)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: QuickRecordingLayout.panelWidth, height: QuickRecordingLayout.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear

        // 设置 SwiftUI 内容（Capsule clipShape 已在 SwiftUI 层处理圆角）
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        // 窗口关闭时更新状态并清理
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.windowVisibility[.quickRecording] = false
            // 如果正在录音，取消录音
            if let vm = self?.viewModels[.quickRecording] as? QuickRecordingViewModel {
                Task { @MainActor in
                    await vm.cancelRecording()
                }
            }
        }

        return panel
    }

    // MARK: - 快速录音专用方法

    /// 显示快速录音窗口并开始录音
    public func showQuickRecordingAndStart() async {
        showWindow(.quickRecording)

        if let viewModel = viewModels[.quickRecording] as? QuickRecordingViewModel {
            await viewModel.startRecording()
        }
    }
}
#endif
