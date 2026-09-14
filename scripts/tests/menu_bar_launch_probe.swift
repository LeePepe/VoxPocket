import AppKit
import SwiftUI

// 测试宿主替换服务/内容，不连接录音、存储或模型；场景和菜单视图直接编译生产源码。
@MainActor enum LLMAppConfig {
    static var shouldFail: Bool { CommandLine.arguments.contains("--configuration-fails") }
    static func loadRuntimeConfiguration() async throws {
        try await Task.sleep(for: .milliseconds(350))
        if shouldFail { throw ProbeError.invalidConfiguration }
    }
}

private enum ProbeError: Error { case invalidConfiguration }

@MainActor private final class ProbeState {
    static let shared = ProbeState()
    var mainContentCreations = 0
    var settingsContentCreations = 0
    var servicesStarted = false
    var openMain: (() -> Void)?
    var openSettings: (() -> Void)?
}

struct ContentView: View {
    init() { ProbeState.shared.mainContentCreations += 1 }
    var body: some View { Text("主窗口测试内容").frame(width: 320, height: 200) }
}

struct SettingsView: View {
    init() { ProbeState.shared.settingsContentCreations += 1 }
    var body: some View { Text("设置测试内容").frame(width: 320, height: 200) }
}

/// 只在测试进程中取得 SwiftUI 场景动作；不点击桌面，不向其他应用注入事件。
private struct ProbeControls: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Image(systemName: "circle")
            .onAppear {
                ProbeState.shared.openMain = { openWindow(id: MacOSAppScenes.mainWindowID) }
                ProbeState.shared.openSettings = { openSettings() }
            }
    }
}

@MainActor private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await verifyScenes() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private var visibleWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    private func require(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }

    private func pause() async { try? await Task.sleep(for: .milliseconds(180)) }

    private func verifyScenes() async {
        let state = ProbeState.shared
        let prepare = Task { await AppStartup.shared.prepare() }
        try? await Task.sleep(for: .milliseconds(80))
        require(visibleWindows.isEmpty, "loading must not show a regular window")
        require(state.mainContentCreations == 0, "loading must keep main content lazy")
        state.servicesStarted = await prepare.value
        await pause()
        require(visibleWindows.isEmpty, "ready/failed startup must not launch a regular window")
        require(state.mainContentCreations == 0 && state.settingsContentCreations == 0,
                "background startup must not construct service-backed window content")
        require(state.servicesStarted == !LLMAppConfig.shouldFail, "configuration gates services without a window")

        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.openMain == nil && ContinuousClock.now < deadline { await pause() }
        require(state.openMain != nil && state.openSettings != nil, "scene commands must be available")
        state.openMain?()
        await pause()
        require(visibleWindows.count == 1, "explicit open must present the main window")
        let mainWindow = visibleWindows[0]
        state.openMain?()
        await pause()
        require(visibleWindows.count == 1 && visibleWindows[0] === mainWindow, "repeated open must reuse main window")
        mainWindow.close()
        await pause()
        require(visibleWindows.isEmpty, "closing main window must leave background app running")

        state.openSettings?()
        await pause()
        require(visibleWindows.count == 1, "settings must open without the main window")
        let settingsWindow = visibleWindows[0]
        state.openSettings?()
        await pause()
        require(visibleWindows.count == 1 && visibleWindows[0] === settingsWindow, "settings must reuse one window")
        if LLMAppConfig.shouldFail {
            require(state.mainContentCreations == 0 && state.settingsContentCreations == 0,
                    "failed configuration must show startup error rather than service-backed content")
        } else {
            require(state.mainContentCreations > 0 && state.settingsContentCreations > 0,
                    "explicit opens must render their ready content")
        }
        print("PASS: menu-first scenes, configuration=\(LLMAppConfig.shouldFail ? "failed" : "ready")")
        exit(0)
    }
}

@main
private struct MenuBarLaunchProbe: App {
    @NSApplicationDelegateAdaptor(ProbeDelegate.self) private var delegate

    var body: some Scene {
        MacOSAppScenes()
        MenuBarExtra { EmptyView() } label: { ProbeControls() }
    }
}
