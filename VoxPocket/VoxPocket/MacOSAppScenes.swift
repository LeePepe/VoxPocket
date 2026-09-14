#if os(macOS)
import AppKit
import SwiftUI
import PlatformUI

/// App 壳只负责场景与生命周期接线；菜单和录音界面继续由 SPM 展示层提供。
@MainActor
struct MacOSAppScenes: Scene {
    static let mainWindowID = "vox-main-window"
    @ObservedObject private var startup = AppStartup.shared

    var body: some Scene {
        Window("VoxPocket", id: Self.mainWindowID) {
            AppStartupView { ContentView() }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MacOSMenuBarContent(startup: startup)
        } label: {
            Label("VoxPocket", systemImage: startup.phase == .failed ? "exclamationmark.triangle" : "waveform")
                .accessibilityIdentifier("vox.menuBar")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            AppStartupView { SettingsView() }
        }
        .restorationBehavior(.disabled)
    }
}

@MainActor
private struct MacOSMenuBarContent: View {
    @ObservedObject var startup: AppStartup
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var configurationStatus: MenuBarConfigurationStatus {
        switch startup.phase {
        case .loading: .loading
        case .ready: .loaded
        case .failed: .failed
        }
    }

    var body: some View {
        VoxMenuBarContent(configurationStatus: configurationStatus) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: MacOSAppScenes.mainWindowID)
        } onOpenSettings: {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } onQuit: {
            NSApp.terminate(nil)
        }
    }
}
#endif
