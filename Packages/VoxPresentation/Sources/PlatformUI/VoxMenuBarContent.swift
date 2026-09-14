#if os(macOS)
import SwiftUI

/// 只表示配置加载状态，不代替麦克风权限、快捷键注册或远端服务可用性检查。
public enum MenuBarConfigurationStatus: CaseIterable, Sendable {
    case loading, loaded, failed

    public var title: String {
        switch self {
        case .loading: "正在加载本机配置…"
        case .loaded: "配置已加载"
        case .failed: "本机配置需要检查"
        }
    }
}

/// 菜单展示留在 SPM；窗口、设置与应用生命周期由 App 壳通过闭包接线。
@MainActor
public struct VoxMenuBarContent: View {
    let configurationStatus: MenuBarConfigurationStatus
    let onOpenMainWindow: (() -> Void)?
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    public init(
        configurationStatus: MenuBarConfigurationStatus,
        onOpenMainWindow: (() -> Void)? = nil,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.configurationStatus = configurationStatus
        self.onOpenMainWindow = onOpenMainWindow
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        Text(configurationStatus.title)
            .accessibilityIdentifier("vox.menu.configuration")
        Divider()
        // 兼容迁移前的 App 壳；新的设置优先入口不传此动作。
        if let onOpenMainWindow {
            Button("打开主窗口…", action: onOpenMainWindow)
                .accessibilityIdentifier("vox.menu.openMainWindow")
        }
        Button("设置…", action: onOpenSettings)
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityIdentifier("vox.menu.settings")
        Divider()
        Button("退出 VoxPocket", action: onQuit)
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityIdentifier("vox.menu.quit")
    }
}
#endif
