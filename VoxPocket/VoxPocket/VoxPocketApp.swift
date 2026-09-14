//
//  VoxPocketApp.swift
//  VoxPocket
//
//  Created by 李天培 on 1/26/26.
//

import SwiftUI
import Preferences
import UseCases
#if os(macOS)
import PlatformAdapters
import Carbon
#endif
import UIShared
#if DEBUG
import UITestingBridge
#endif

@main
enum VoxPocketEntryPoint {
    @MainActor
    static func main() {
        // App.main() 必须从同步入口启动；从挂起后的主队列任务调用会饿死后续任务。
        VoxPocketApp.main()
    }
}

struct VoxPocketApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    init() {
        #if DEBUG
        UITestingBridge.start()
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // macOS 只保留菜单栏、快捷浮窗与独立设置。
        MacOSAppScenes()
        #else
        // iOS: 标准窗口组
        WindowGroup {
            AppStartupView { ContentView() }
                .onOpenURL { url in
                    Task { @MainActor in
                        guard await AppStartup.shared.prepare() else { return }
                        ServiceContainer.shared.deepLinkRouter.handle(url)
                    }
                }
        }
        // 不使用 .modelContainer() — repository 直接持有 container 引用
        #endif
    }
}
