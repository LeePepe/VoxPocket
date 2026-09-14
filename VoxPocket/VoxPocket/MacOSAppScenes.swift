#if os(macOS)
import AppKit
import SwiftUI
import PlatformUI

/// App 壳只负责场景与生命周期接线；菜单和录音界面继续由 SPM 展示层提供。
@MainActor
struct MacOSAppScenes: Scene {
    @ObservedObject private var startup = AppStartup.shared

    var body: some Scene {
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
    @Environment(\.openSettings) private var openSettings

    private var configurationStatus: MenuBarConfigurationStatus {
        switch startup.phase {
        case .loading: .loading
        case .ready: .loaded
        case .failed: .failed
        }
    }

    var body: some View {
        VoxMenuBarContent(configurationStatus: configurationStatus, onOpenSettings: {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }, onQuit: {
            NSApp.terminate(nil)
        })
    }
}
#endif
