//
//  VoxPocketApp.swift
//  VoxPocket
//
//  Created by 李天培 on 1/26/26.
//

import SwiftUI
import Preferences
import UseCases
import OSLog
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
    static func main() async {
        do {
            try await LLMAppConfig.loadRuntimeConfiguration()
        } catch {
            // 配置无效时不创建任何模型服务；诊断固定且不包含配置内容。
            let message = (error as? PrivateModelConfigurationError)?.errorDescription ?? "无法加载本机模型配置。"
            Logger(subsystem: "com.leepepe.voxpocket", category: "ModelConfiguration")
                .error("\(message, privacy: .public)")
            await Task.detached {
                FileHandle.standardError.write(Data((message + "\n").utf8))
            }.value
            return
        }
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
        // macOS: 主窗口 + 设置窗口
        WindowGroup("VoxPocket") {
            ContentView()
        }
        // 不使用 .modelContainer() — repository 直接持有 container 引用

        // 设置窗口（可选）
        Settings {
            SettingsView()
        }
        #else
        // iOS: 标准窗口组
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    ServiceContainer.shared.deepLinkRouter.handle(url)
                }
        }
        // 不使用 .modelContainer() — repository 直接持有 container 引用
        #endif
    }
}

// MARK: - 设置视图

#if os(macOS)
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("General settings will be added here.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ShortcutsSettingsView: View {
    @StateObject private var viewModel = ShortcutsViewModel()

    var body: some View {
        Form {
            Section("Global Shortcuts") {
                HStack {
                    Text("Show Panel")
                    Spacer()
                    Text(viewModel.showPanelDisplayName)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                HStack {
                    Text("Quick Recording")
                    Spacer()
                    Text("\(viewModel.quickRecordDisplayName) (hold)")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Section {
                Text("Hold the Quick Recording shortcut for 0.5 seconds to start recording. Release to process and paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear {
            Task { await viewModel.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PreferencesNotification.hotkeysDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }
}
#endif
