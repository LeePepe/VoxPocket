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
import TranscriptionKit

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
    private let quickRecordDismissWindow: (@MainActor @Sendable () -> Bool)?
    private let quickRecordSaveSession: (@MainActor @Sendable (String, String) async throws -> Void)?
    private let quickRecordTrack: (@MainActor @Sendable (String, [String: String]) -> Void)?
    private var quickRecordingSession: QuickRecordingSession?
    private struct QuickRecordingSession {
        let id: UUID
        let viewModel: QuickRecordingViewModel
        var released = false
        var completing = false
    }
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
        quickRecordDismissWindow = nil
        quickRecordSaveSession = nil
        quickRecordTrack = nil
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
        quickRecordHideWindow: (@MainActor @Sendable () -> Void)? = nil,
        quickRecordDismissWindow: (@MainActor @Sendable () -> Bool)? = nil,
        quickRecordSaveSession: (@MainActor @Sendable (String, String) async throws -> Void)? = nil,
        quickRecordTrack: (@MainActor @Sendable (String, [String: String]) -> Void)? = nil
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
        self.quickRecordDismissWindow = quickRecordDismissWindow
        self.quickRecordSaveSession = quickRecordSaveSession
        self.quickRecordTrack = quickRecordTrack
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

    // QUICK_RECORD_HANDLERS_BEGIN
    /// 处理快速录音开始（按下触发）
    private func handleQuickRecordStart() async {
        quickRecordStartCount += 1
        logger.log(.debug, "Quick record start triggered", context: ["call_count": quickRecordStartCount])
        guard claimQuickRecording() else { return }
        showQuickRecordingWindow()
        guard let viewModel = currentQuickRecordingViewModel() else {
            closeQuickRecordingWindow()
            endQuickRecording()
            return
        }
        let session = QuickRecordingSession(id: UUID(), viewModel: viewModel)
        quickRecordingSession = session
        installQuickRecordingCallbacks(session)
        await viewModel.startRecording()
        if viewModel.recorderStatus == .error {
            finishQuickRecording(session.id)
            return
        }
        ProductTelemetryNotificationBoundary.postQuickRecordStarted(to: productTelemetryNotificationCenter)
        if viewModel.recorderStatus != .listening {
            ProductTelemetryNotificationBoundary.postQuickRecordStopped(to: productTelemetryNotificationCenter)
        }
    }

    /// 处理快速录音结束（释放触发）
    private func handleQuickRecordStop() async {
        let releasedAt = ContinuousClock.now
        quickRecordStopCount += 1
        logger.log(.debug, "Quick record stop triggered", context: ["call_count": quickRecordStopCount])
        guard activeQuickRecordingSource() == .quickRecording,
              var session = quickRecordingSession, !session.released else { return }
        guard let viewModel = currentQuickRecordingViewModel(), viewModel === session.viewModel else {
            finishQuickRecording(session.id)
            return
        }
        session.released = true
        quickRecordingSession = session
        trackQuickRecording(.quickRecordFnReleased, sessionID: session.id)
        if dismissQuickRecordingWindow() {
            let elapsed = releasedAt.duration(to: .now).components
            let milliseconds = max(0, Double(elapsed.seconds) * 1_000
                + Double(elapsed.attoseconds) / 1_000_000_000_000_000)
            trackQuickRecording(.quickRecordPanelClosed, sessionID: session.id,
                                properties: ["duration_ms": String(milliseconds)])
        }
        let stoppedDuringStartup = viewModel.isStartingRecording
        let wasListening = viewModel.recorderStatus == .listening
        await viewModel.stopRecording()
        if !stoppedDuringStartup, viewModel.recorderStatus == .idle || viewModel.recorderStatus == .error {
            finishQuickRecording(session.id)
        }
        if wasListening, viewModel.recorderStatus != .listening {
            ProductTelemetryNotificationBoundary.postQuickRecordStopped(to: productTelemetryNotificationCenter)
        }
    }

    private func installQuickRecordingCallbacks(_ session: QuickRecordingSession) {
        let sessionID = session.id
        session.viewModel.onComplete = { [weak self, weak viewModel = session.viewModel] finalText in
            guard let self, var current = self.quickRecordingSession,
                  current.id == sessionID, !current.completing else { return }
            current.completing = true
            self.quickRecordingSession = current
            let rawText = viewModel?.rawTranscription ?? finalText
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.finishQuickRecording(sessionID) }
                try? await self.saveQuickRecording(rawText: rawText, finalText: finalText)
            }
        }
        session.viewModel.onNoResult = { [weak self] in
            guard let self, let current = self.quickRecordingSession,
                  current.id == sessionID, !current.completing else { return }
            self.finishQuickRecording(sessionID)
        }
    }

    private func finishQuickRecording(_ sessionID: UUID) {
        guard let session = quickRecordingSession, session.id == sessionID else { return }
        quickRecordingSession = nil
        session.viewModel.onComplete = nil
        session.viewModel.onNoResult = nil
        closeQuickRecordingWindow()
        endQuickRecording()
    }

    private func claimQuickRecording() -> Bool {
        #if DEBUG
        if let quickRecordTryStart { return quickRecordTryStart(.quickRecording) }
        #endif
        return serviceContainer.tryStartRecording(source: .quickRecording)
    }

    private func activeQuickRecordingSource() -> RecordingSource? {
        #if DEBUG
        if let quickRecordActiveSource { return quickRecordActiveSource() }
        #endif
        return serviceContainer.activeRecordingSource
    }

    private func currentQuickRecordingViewModel() -> QuickRecordingViewModel? {
        #if DEBUG
        if let quickRecordViewModel { return quickRecordViewModel() }
        #endif
        return windowManager.getQuickRecordingViewModel()
    }

    private func showQuickRecordingWindow() {
        #if DEBUG
        if let quickRecordShowWindow { quickRecordShowWindow(); return }
        #endif
        windowManager.showWindow(.quickRecording)
    }

    private func dismissQuickRecordingWindow() -> Bool {
        #if DEBUG
        if let quickRecordDismissWindow { return quickRecordDismissWindow() }
        #endif
        return windowManager.dismissQuickRecordingWindow()
    }

    private func closeQuickRecordingWindow() {
        #if DEBUG
        if let quickRecordHideWindow { quickRecordHideWindow(); return }
        #endif
        windowManager.hideWindow(.quickRecording)
    }

    private func endQuickRecording() {
        #if DEBUG
        if let quickRecordEnd { quickRecordEnd(); return }
        #endif
        serviceContainer.endRecording()
    }

    private func saveQuickRecording(rawText: String, finalText: String) async throws {
        #if DEBUG
        if let quickRecordSaveSession { try await quickRecordSaveSession(rawText, finalText); return }
        #endif
        await serviceContainer.initializePersistence()
        try await serviceContainer.sessionUseCase.saveCompletedSession(
            title: nil, rawText: rawText, refinedText: finalText
        )
    }

    private func trackQuickRecording(
        _ event: VoxPocketTelemetryEventName,
        sessionID: UUID,
        properties: [String: String] = [:]
    ) {
        let metrics = properties.merging(["source": "quick", "session_id": sessionID.uuidString]) { _, fixed in fixed }
        #if DEBUG
        if let quickRecordTrack { quickRecordTrack(event.rawValue, metrics); return }
        #endif
        serviceContainer.telemetryService.track(name: event.rawValue, properties: metrics)
    }
    // QUICK_RECORD_HANDLERS_END
}
#endif
