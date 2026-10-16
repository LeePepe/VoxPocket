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
import LokiKit

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
    private var hotkeyService: (any GlobalHotkeyService)!
    private let preferences = UserDefaultsPreferencesStore.shared
    private let logger: Logger = PrintLogger(subsystem: "AppDelegate")
    private let productTelemetryNotificationCenter: NotificationCenter
    private let startup: AppStartup
    private let serviceContainerReference: ServiceContainer?
    private let windowManagerReference: WindowManager
    private let hotkeyServiceReference: any GlobalHotkeyService
    private let startupInitializePersistence: (@MainActor @Sendable () async -> Void)?
    private let startupScheduleQuickRecordingPrewarm: (@MainActor @Sendable () -> Void)?
    private let quickRecordTryStart: (@MainActor @Sendable (RecordingSource) -> Bool)?
    private let quickRecordActiveSource: (@MainActor @Sendable () -> RecordingSource?)?
    private let quickRecordEnd: (@MainActor @Sendable () -> Void)?
    private let quickRecordShowWindow: (@MainActor @Sendable () -> Void)?
    private let quickRecordViewModel: (@MainActor @Sendable () -> QuickRecordingViewModel?)?
    private let quickRecordHideWindow: (@MainActor @Sendable () -> Void)?
    private var startupTask: Task<Void, Never>?
    private var resignActiveTask: Task<Void, Never>?
    private let launchStartedAt = ContinuousClock.now

    // DEBUG: 追踪 start/stop 调用次数
    private var quickRecordStartCount = 0
    private var quickRecordStopCount = 0

    public override init() {
        productTelemetryNotificationCenter = .default
        startup = .shared
        serviceContainerReference = nil
        windowManagerReference = .shared
        hotkeyServiceReference = MacOSGlobalHotkeyService.shared
        startupInitializePersistence = nil
        startupScheduleQuickRecordingPrewarm = nil
        quickRecordTryStart = nil
        quickRecordActiveSource = nil
        quickRecordEnd = nil
        quickRecordShowWindow = nil
        quickRecordViewModel = nil
        quickRecordHideWindow = nil
        super.init()
    }

    init(
        productTelemetryNotificationCenter: NotificationCenter,
        startup: AppStartup = .shared,
        serviceContainer: ServiceContainer? = nil,
        windowManager: WindowManager = .shared,
        hotkeyService: any GlobalHotkeyService = MacOSGlobalHotkeyService.shared,
        startupInitializePersistence: (@MainActor @Sendable () async -> Void)? = nil,
        startupScheduleQuickRecordingPrewarm: (@MainActor @Sendable () -> Void)? = nil,
        quickRecordTryStart: (@MainActor @Sendable (RecordingSource) -> Bool)? = nil,
        quickRecordActiveSource: (@MainActor @Sendable () -> RecordingSource?)? = nil,
        quickRecordEnd: (@MainActor @Sendable () -> Void)? = nil,
        quickRecordShowWindow: (@MainActor @Sendable () -> Void)? = nil,
        quickRecordViewModel: (@MainActor @Sendable () -> QuickRecordingViewModel?)? = nil,
        quickRecordHideWindow: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.productTelemetryNotificationCenter = productTelemetryNotificationCenter
        self.startup = startup
        serviceContainerReference = serviceContainer
        windowManagerReference = windowManager
        hotkeyServiceReference = hotkeyService
        self.startupInitializePersistence = startupInitializePersistence
        self.startupScheduleQuickRecordingPrewarm = startupScheduleQuickRecordingPrewarm
        self.quickRecordTryStart = quickRecordTryStart
        self.quickRecordActiveSource = quickRecordActiveSource
        self.quickRecordEnd = quickRecordEnd
        self.quickRecordShowWindow = quickRecordShowWindow
        self.quickRecordViewModel = quickRecordViewModel
        self.quickRecordHideWindow = quickRecordHideWindow
        super.init()
    }

    // MARK: - NSApplicationDelegate

    public func applicationDidFinishLaunching(_ notification: Notification) {
        logger.debug("Application did finish launching")

        // 单实例保护：若已有 VoxPocket 实例在跑（例如已装的 /Applications 版 +
        // 从 Xcode DerivedData 启动的 Debug 版），激活已有实例并终止自己，
        // 避免两个实例都注册 Fn 全局热键导致按一次弹两个 panel。
        // 同一路径的实例由 Info.plist 的 LSMultipleInstancesProhibited 拦截；
        // 这段是不同路径 / 不同 build 场景的兜底。
        //
        // 例外：在 XCTest / SwiftPM 测试宿主下运行时不做单实例检查，
        // 否则测试宿主会被开发机上已跑着的 VoxPocket 误当作重复实例杀掉，
        // 导致 test runner 连接失败。
        let env = ProcessInfo.processInfo.environment
        let isMarkedUITestHost = env[ServiceContainer.uiTestHostEnvironmentKey] == "1"
            && ProcessInfo.processInfo.arguments.contains("--vox-ui-test-host")
        let isRunningTests = env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || isMarkedUITestHost
        if !isRunningTests,
           let bundleId = Bundle.main.bundleIdentifier,
           case .another(let pid) = SingleInstanceGuard.evaluateAndActivateExisting(bundleId: bundleId) {
            logger.log(.debug, "Another VoxPocket instance is running, activating it and quitting self", context: [
                "existing_pid": pid,
                "self_pid": ProcessInfo.processInfo.processIdentifier
            ])
            NSApp.terminate(nil)
            return
        }

        // 启动系统事件循环后再等待配置；服务和快捷键都不能抢在配置之前初始化。
        startupTask = Task { @MainActor [weak self] in
            guard let self, await startup.prepare(), !Task.isCancelled else { return }
            setupServices()
            await serviceContainer.completeProductTelemetryStartup(startedAt: launchStartedAt)
            if let startupScheduleQuickRecordingPrewarm {
                startupScheduleQuickRecordingPrewarm()
            } else {
                windowManager.scheduleQuickRecordingPrewarm()
            }
            observePreferenceChanges()
            await registerHotkeys()
            // 主窗口已退出 macOS 主流程，存储仍须在后台初始化；磁盘打开不阻塞热键。
            if let startupInitializePersistence {
                await startupInitializePersistence()
            } else {
                await serviceContainer.initializePersistence()
            }
            logger.debug("Initialization complete")
        }

        // 隐藏 Dock 图标（可选）
        // NSApp.setActivationPolicy(.accessory)

    }

    public func applicationWillTerminate(_ notification: Notification) {
        logger.debug("Application will terminate")
        startupTask?.cancel()

        // 注销所有快捷键
        hotkeyService?.unregisterAll()
    }

    public func applicationWillResignActive(_ notification: Notification) {
        guard let serviceContainer else { return }
        resignActiveTask = Task {
            await serviceContainer.productTelemetryApplicationWillResignActive()
        }
    }

    func waitForPendingStartup() async {
        await startupTask?.value
    }

    func waitForPendingProductTelemetryResignActive() async {
        await resignActiveTask?.value
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 保持应用运行，即使所有窗口关闭
        return false
    }

    // MARK: - 服务初始化

    private func setupServices() {
        serviceContainer = serviceContainerReference ?? ServiceContainer.shared
        windowManager = windowManagerReference
        hotkeyService = hotkeyServiceReference

        logger.debug("Services initialized")
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
            logger.log(.debug, "Registered show panel hotkey", context: [
                "identifier": HotkeyIdentifier.showPopover,
                "display": showPanelHotkey.displayString
            ])
        } catch {
            logger.log(.debug, "Failed to register show panel hotkey", context: [
                "identifier": HotkeyIdentifier.showPopover,
                "error": error.localizedDescription
            ])
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
        logger.log(.debug, "Registered quick record hotkey", context: [
            "identifier": HotkeyIdentifier.toggleRecording,
            "display": quickRecordHotkey.displayString,
            "mode": "press_release"
        ])
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
        logger.debug("Show panel hotkey triggered")
        windowManager.toggleWindow(.fullPanel)
        if windowManager.windowVisibility[.fullPanel] == true {
            ProductTelemetryNotificationBoundary.postFullPanelOpened()
        }
    }

    /// 处理快速录音开始（按下触发）
    func enterQuickRecordStart() async {
        await handleQuickRecordStart()
    }

    func enterQuickRecordStop() async {
        await handleQuickRecordStop()
    }

    private func handleQuickRecordStart() async {
        quickRecordStartCount += 1
        logger.log(.debug, "Quick record start triggered", context: ["call_count": quickRecordStartCount])

        #if DEBUG
        let claimRecording = quickRecordTryStart ?? { self.serviceContainer.tryStartRecording(source: $0) }
        let showQuickRecording = quickRecordShowWindow ?? { self.windowManager.showWindow(.quickRecording) }
        let getQuickRecordingViewModel =
            quickRecordViewModel ?? { self.windowManager.getQuickRecordingViewModel() }
        let endQuickRecording = quickRecordEnd ?? { [weak self] in
            guard let self else { return }
            self.serviceContainer.endRecording()
        }
        let hideQuickRecording =
            quickRecordHideWindow ?? { [weak self] in
                guard let self else { return }
                self.windowManager.hideWindow(.quickRecording)
            }
        #else
        let claimRecording = { self.serviceContainer.tryStartRecording(source: $0) }
        let showQuickRecording = { self.windowManager.showWindow(.quickRecording) }
        let getQuickRecordingViewModel = { self.windowManager.getQuickRecordingViewModel() }
        let endQuickRecording = { [weak self] in
            guard let self else { return }
            self.serviceContainer.endRecording()
        }
        let hideQuickRecording = { [weak self] in
            guard let self else { return }
            self.windowManager.hideWindow(.quickRecording)
        }
        #endif

        let performStart = { [self] in
            guard claimRecording(.quickRecording) else {
                return (
                    didStart: false,
                    status: getQuickRecordingViewModel()?.recorderStatus ?? .error
                )
            }

            // 先创建面板；关闭回调必须在异步启动前就绪，避免快速松手的无结果回调丢失。
            showQuickRecording()

            // 设置完成回调：隐藏面板 + 清除录音状态
            if let viewModel = getQuickRecordingViewModel() {
                viewModel.onComplete = { [weak self, weak viewModel] finalText in
                    Task { @MainActor in
                        // 保存会话到持久化存储
                        let raw = viewModel?.rawTranscription ?? finalText
                        await self?.serviceContainer.initializePersistence()
                        try? await self?.serviceContainer.sessionUseCase.saveCompletedSession(
                            title: nil,
                            rawText: raw,
                            refinedText: finalText
                        )

                        try? await Task.sleep(for: .seconds(1))
                        hideQuickRecording()
                        endQuickRecording()
                    }
                }
                viewModel.onNoResult = { [weak self] in
                    Task { @MainActor in
                        guard self != nil else { return }
                        hideQuickRecording()
                        endQuickRecording()
                    }
                }

                await viewModel.startRecording()
                return (true, viewModel.recorderStatus)
            }
            return (
                false,
                getQuickRecordingViewModel()?.recorderStatus ?? .error
            )
        }

        #if canImport(LokiKit)
        let telemetryResult = await performStart()
        guard telemetryResult.didStart, telemetryResult.status != .error else { return }
        ProductTelemetryNotificationBoundary.postQuickRecordStarted(
            to: productTelemetryNotificationCenter
        )
        if telemetryResult.status != .listening {
            ProductTelemetryNotificationBoundary.postQuickRecordStopped(
                to: productTelemetryNotificationCenter
            )
        }
        #else
        _ = await performStart()
        #endif
    }

    /// 处理快速录音结束（释放触发）
    private func handleQuickRecordStop() async {
        quickRecordStopCount += 1
        logger.log(.debug, "Quick record stop triggered", context: ["call_count": quickRecordStopCount])

        #if DEBUG
        let activeQuickRecordingSource =
            quickRecordActiveSource ?? { self.serviceContainer.activeRecordingSource }
        let getQuickRecordingViewModel =
            quickRecordViewModel ?? { self.windowManager.getQuickRecordingViewModel() }
        let endQuickRecording = quickRecordEnd ?? { [weak self] in
            guard let self else { return }
            self.serviceContainer.endRecording()
        }
        let hideQuickRecording =
            quickRecordHideWindow ?? { [weak self] in
                guard let self else { return }
                self.windowManager.hideWindow(.quickRecording)
            }
        #else
        let activeQuickRecordingSource = { self.serviceContainer.activeRecordingSource }
        let getQuickRecordingViewModel = { self.windowManager.getQuickRecordingViewModel() }
        let endQuickRecording = { [weak self] in
            guard let self else { return }
            self.serviceContainer.endRecording()
        }
        let hideQuickRecording = { [weak self] in
            guard let self else { return }
            self.windowManager.hideWindow(.quickRecording)
        }
        #endif

        let performStop = { [self] in
            let activeSource = activeQuickRecordingSource()
            guard activeSource == .quickRecording else {
                logger.log(.debug, "Recording source mismatch on quick record stop", context: [
                    "active_source": activeSource?.rawValue ?? "nil"
                ])
                return (
                    shouldHandle: false,
                    stoppedDuringStartup: false,
                    wasListening: false,
                    status: getQuickRecordingViewModel()?.recorderStatus ?? .idle
                )
            }

            guard let viewModel = getQuickRecordingViewModel() else {
                endQuickRecording()
                return (
                    false,
                    false,
                    false,
                    getQuickRecordingViewModel()?.recorderStatus ?? .idle
                )
            }

            let stoppedDuringStartup = viewModel.isStartingRecording
            let wasListening = viewModel.recorderStatus == .listening
            await viewModel.stopRecording()

            if stoppedDuringStartup {
                // 启动尚未完成，等待 ViewModel 在 start 完成后自动 stop 并通过回调清理
                return (true, true, wasListening, viewModel.recorderStatus)
            }

            // 兜底清理：如果没有进入转录/优化流程，立即释放录音占用，避免状态卡死
            switch viewModel.recorderStatus {
            case .idle:
                logger.debug("handleQuickRecordStop: fallback cleanup triggered, status=\(String(describing: viewModel.recorderStatus))")
                endQuickRecording()
                hideQuickRecording()
            case .error:
                // 释放录音占用以便 Fn 重试，但保留错误岛供用户复制已识别原文或关闭。
                endQuickRecording()
            case .listening, .transcribing, .refining, .done:
                break
            }
            return (true, false, wasListening, viewModel.recorderStatus)
        }

        #if canImport(LokiKit)
        let telemetryResult = await performStop()
        guard telemetryResult.shouldHandle, !telemetryResult.stoppedDuringStartup else { return }
        if telemetryResult.wasListening, telemetryResult.status != .listening {
            ProductTelemetryNotificationBoundary.postQuickRecordStopped(
                to: productTelemetryNotificationCenter
            )
        }
        #else
        _ = await performStop()
        #endif
    }
}

#endif
