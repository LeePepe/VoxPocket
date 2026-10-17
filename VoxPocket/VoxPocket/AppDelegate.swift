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
        guard !activateExistingInstanceIfNeeded() else { return }
        scheduleStartup()
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
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
            return true
        }
        return false
    }

    private func scheduleStartup() {
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
        let quickRecordHotkey = await resolvedQuickRecordHotkey()
        registerShowPanelHotkey(showPanelHotkey)
        registerQuickRecordHotkey(quickRecordHotkey)
    }

    private func resolvedQuickRecordHotkey() async -> HotkeyDefinition {
        var hotkey = await preferences.getValue(
            for: .quickRecordHotkey,
            default: Self.defaultQuickRecordHotkey
        )
        if hotkey.keyCode == UInt16(kVK_F6), hotkey.modifiers == 0 {
            hotkey = Self.defaultQuickRecordHotkey
            await preferences.setValue(hotkey, for: .quickRecordHotkey)
        }
        return hotkey
    }

    private func registerShowPanelHotkey(_ hotkey: HotkeyDefinition) {
        do {
            try hotkeyService.register(hotkey) { [weak self] in
                Task { @MainActor in
                    self?.handleShowPanelHotkey()
                }
            }
            logger.log(.debug, "Registered show panel hotkey", context: [
                "identifier": HotkeyIdentifier.showPopover,
                "display": hotkey.displayString
            ])
        } catch {
            logger.log(.debug, "Failed to register show panel hotkey", context: [
                "identifier": HotkeyIdentifier.showPopover,
                "error": error.localizedDescription
            ])
        }
    }

    private func registerQuickRecordHotkey(_ hotkey: HotkeyDefinition) {
        hotkeyService.registerLongPress(
            hotkey,
            onPress: { [weak self] in
                await self?.handleQuickRecordStart()
            },
            onRelease: { [weak self] in
                await self?.handleQuickRecordStop()
            }
        )
        logger.log(.debug, "Registered quick record hotkey", context: [
            "identifier": HotkeyIdentifier.toggleRecording,
            "display": hotkey.displayString,
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
    private func handleQuickRecordStart() async {
        quickRecordStartCount += 1
        logger.log(.debug, "Quick record start triggered", context: ["call_count": quickRecordStartCount])
        #if DEBUG
        let claim = quickRecordTryStart ?? { self.serviceContainer.tryStartRecording(source: $0) }
        let show = quickRecordShowWindow ?? { self.windowManager.showWindow(.quickRecording) }
        let model = quickRecordViewModel ?? { self.windowManager.getQuickRecordingViewModel() }
        let end = quickRecordEnd ?? { [weak self] in self?.serviceContainer.endRecording() }
        let hide = quickRecordHideWindow ?? { [weak self] in self?.windowManager.hideWindow(.quickRecording) }
        #else
        let claim = { self.serviceContainer.tryStartRecording(source: $0) }
        let show = { self.windowManager.showWindow(.quickRecording) }
        let model = { self.windowManager.getQuickRecordingViewModel() }
        let end = { [weak self] in self?.serviceContainer.endRecording() }
        let hide = { [weak self] in self?.windowManager.hideWindow(.quickRecording) }
        #endif
        guard claim(.quickRecording) else { return }
        show()
        guard let viewModel = model() else { return }
        viewModel.onComplete = { [weak self, weak viewModel] finalText in
            Task { @MainActor in
                let raw = viewModel?.rawTranscription ?? finalText
                await self?.serviceContainer.initializePersistence()
                try? await self?.serviceContainer.sessionUseCase.saveCompletedSession(
                    title: nil, rawText: raw, refinedText: finalText
                )
                try? await Task.sleep(for: .seconds(1))
                hide(); end()
            }
        }
        viewModel.onNoResult = { Task { @MainActor in hide(); end() } }
        await viewModel.startRecording()
        #if canImport(LokiKit)
        guard viewModel.recorderStatus != .error else { return }
        ProductTelemetryNotificationBoundary.postQuickRecordStarted(
            to: productTelemetryNotificationCenter
        )
        if viewModel.recorderStatus != .listening {
            ProductTelemetryNotificationBoundary.postQuickRecordStopped(
                to: productTelemetryNotificationCenter
            )
        }
        #endif
    }

    /// 处理快速录音结束（释放触发）
    private func handleQuickRecordStop() async {
        quickRecordStopCount += 1
        logger.log(.debug, "Quick record stop triggered", context: ["call_count": quickRecordStopCount])
        #if DEBUG
        let source = quickRecordActiveSource ?? { self.serviceContainer.activeRecordingSource }
        let model = quickRecordViewModel ?? { self.windowManager.getQuickRecordingViewModel() }
        let end = quickRecordEnd ?? { [weak self] in self?.serviceContainer.endRecording() }
        let hide = quickRecordHideWindow ?? { [weak self] in self?.windowManager.hideWindow(.quickRecording) }
        #else
        let source = { self.serviceContainer.activeRecordingSource }
        let model = { self.windowManager.getQuickRecordingViewModel() }
        let end = { [weak self] in self?.serviceContainer.endRecording() }
        let hide = { [weak self] in self?.windowManager.hideWindow(.quickRecording) }
        #endif
        guard source() == .quickRecording else {
            logger.debug("Recording source mismatch on quick record stop")
            return
        }
        guard let viewModel = model() else { end(); return }
        let stoppedDuringStartup = viewModel.isStartingRecording
        let wasListening = viewModel.recorderStatus == .listening
        await viewModel.stopRecording()
        guard !stoppedDuringStartup else { return }
        switch viewModel.recorderStatus {
        case .idle: end(); hide()
        case .error: end()
        case .listening, .transcribing, .refining, .done: break
        }
        #if canImport(LokiKit)
        if wasListening, viewModel.recorderStatus != .listening {
            ProductTelemetryNotificationBoundary.postQuickRecordStopped(
                to: productTelemetryNotificationCenter
            )
        }
        #endif
    }

}

#endif
