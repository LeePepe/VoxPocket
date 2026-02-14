//
//  AppDelegate.swift
//  VoxPocket
//
//  macOS 应用代理，管理全局快捷键和服务生命周期
//

#if os(macOS)
import Foundation
import AppKit
import Carbon
import PlatformAdapters
import PlatformUI
import UIShared
import UseCases
import Preferences

/// macOS 应用代理
///
/// 负责：
/// - 初始化全局服务
/// - 注册全局快捷键
/// - 管理窗口生命周期
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 服务引用

    private var serviceContainer: ServiceContainer!
    private var windowManager: WindowManager!
    private var hotkeyService: MacOSGlobalHotkeyService!
    private let preferences = UserDefaultsPreferencesStore.shared

    // MARK: - NSApplicationDelegate

    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 [AppDelegate] Application did finish launching")

        // 初始化服务
        setupServices()

        // 注册全局快捷键
        Task { @MainActor in
            await registerHotkeys()
        }
        observePreferenceChanges()

        // 隐藏 Dock 图标（可选）
        // NSApp.setActivationPolicy(.accessory)

        print("✅ [AppDelegate] Initialization complete")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        print("👋 [AppDelegate] Application will terminate")

        // 注销所有快捷键
        hotkeyService?.unregisterAll()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 保持应用运行，即使所有窗口关闭
        return false
    }

    // MARK: - 服务初始化

    private func setupServices() {
        serviceContainer = ServiceContainer.shared
        windowManager = WindowManager.shared
        hotkeyService = MacOSGlobalHotkeyService.shared

        print("📦 [AppDelegate] Services initialized")
    }

    // MARK: - 快捷键注册

    private func registerHotkeys() async {
        hotkeyService.unregister(HotkeyIdentifier.showPopover)
        hotkeyService.unregister(HotkeyIdentifier.toggleRecording)

        // 快捷键定义
        // F7: 显示/隐藏完整面板
        let showPanelHotkey = await preferences.getValue(
            for: .showPanelHotkey,
            default: Self.defaultShowPanelHotkey
        )

        // Fn: 快速录音（按下开始 / 抬起结束）
        var quickRecordHotkey = await preferences.getValue(
            for: .quickRecordHotkey,
            default: Self.defaultQuickRecordHotkey
        )
        if quickRecordHotkey.keyCode == UInt16(kVK_F6), quickRecordHotkey.modifiers == 0 {
            quickRecordHotkey = Self.defaultQuickRecordHotkey
            await preferences.setValue(quickRecordHotkey, for: .quickRecordHotkey)
        }

        // 注册显示面板快捷键
        do {
            try hotkeyService.register(showPanelHotkey) { [weak self] in
                Task { @MainActor in
                    self?.handleShowPanelHotkey()
                }
            }
            print("✅ [AppDelegate] Registered show panel hotkey: F7")
        } catch {
            print("❌ [AppDelegate] Failed to register show panel hotkey: \(error)")
        }

        // 注册快速录音快捷键（按下/抬起模式）
        hotkeyService.registerLongPress(
            quickRecordHotkey,
            onPress: { [weak self] in
                await self?.handleQuickRecordStart()
            },
            onRelease: { [weak self] in
                await self?.handleQuickRecordStop()
            }
        )
        print("✅ [AppDelegate] Registered quick record hotkey: \(quickRecordHotkey.displayString) (press/release)")
    }

    private func observePreferenceChanges() {
        NotificationCenter.default.addObserver(
            forName: PreferencesNotification.hotkeysDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.registerHotkeys()
            }
        }
    }

    private static let defaultShowPanelHotkey = HotkeyDefinition(
        keyCode: UInt16(kVK_F7),
        modifiers: 0,
        identifier: HotkeyIdentifier.showPopover
    )

    private static let defaultQuickRecordHotkey = HotkeyDefinition(
        keyCode: UInt16(kVK_Function),
        modifiers: 0,
        identifier: HotkeyIdentifier.toggleRecording
    )

    // MARK: - 快捷键处理

    /// 处理显示面板快捷键
    private func handleShowPanelHotkey() {
        print("🔥 [AppDelegate] Show panel hotkey triggered")
        windowManager.toggleWindow(.fullPanel)
    }

    /// 处理快速录音开始（按下触发）
    private func handleQuickRecordStart() async {
        print("🔥 [AppDelegate] Quick record start (press)")

        guard serviceContainer.tryStartRecording(source: .quickRecording) else {
            return
        }

        // 显示面板并开始录音
        await windowManager.showQuickRecordingAndStart()

        // 设置完成回调：隐藏面板 + 清除录音状态
        if let viewModel = windowManager.getQuickRecordingViewModel() {
            viewModel.onComplete = { [weak self, weak viewModel] finalText in
                Task { @MainActor in
                    // 保存会话到持久化存储
                    let raw = viewModel?.rawTranscription ?? finalText
                    try? await self?.serviceContainer.sessionUseCase.saveCompletedSession(
                        title: nil,
                        rawText: raw,
                        refinedText: finalText
                    )

                    try? await Task.sleep(for: .seconds(1))
                    self?.windowManager.hideWindow(.quickRecording)
                    self?.serviceContainer.endRecording()
                }
            }
            viewModel.onNoResult = { [weak self] in
                Task { @MainActor in
                    self?.windowManager.hideWindow(.quickRecording)
                    self?.serviceContainer.endRecording()
                }
            }
        }
    }

    /// 处理快速录音结束（释放触发）
    private func handleQuickRecordStop() async {
        print("🔥 [AppDelegate] Quick record stop (release)")

        guard serviceContainer.activeRecordingSource == .quickRecording else {
            print("⚠️ [AppDelegate] Recording not from quick recording, ignoring")
            return
        }

        guard let viewModel = windowManager.getQuickRecordingViewModel() else {
            serviceContainer.endRecording()
            return
        }

        await viewModel.stopRecording()

        if viewModel.isStartingRecording {
            // 启动尚未完成，等待 ViewModel 在 start 完成后自动 stop 并通过回调清理
            return
        }

        // 兜底清理：如果没有进入转录/优化流程，立即释放录音占用，避免状态卡死
        switch viewModel.recorderStatus {
        case .idle, .error:
            serviceContainer.endRecording()
            windowManager.hideWindow(.quickRecording)
        case .listening, .transcribing, .refining, .done:
            break
        }
    }
}
#endif
