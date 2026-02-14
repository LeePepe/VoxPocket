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

@main
struct VoxPocketApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

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
