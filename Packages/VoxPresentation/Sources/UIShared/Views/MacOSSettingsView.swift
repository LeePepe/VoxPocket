#if os(macOS)
import SwiftUI
import Preferences

/// 原生设置复用「我的」的偏好模型，不创建编辑器、会话或录音服务。
@MainActor
public struct MacOSSettingsView: View {
    @StateObject private var providerSettings: LLMProviderSettingsViewModel
    @StateObject private var shortcuts: ShortcutsViewModel
    @State private var isLoaded = false
    @State private var selection: Section = .shortcuts
    let localModelLoadingStatus: LocalModelLoadingStatus?
    enum Section: Hashable { case shortcuts, text }

    public init(
        providerSettings: LLMProviderSettingsViewModel = LLMProviderSettingsViewModel(),
        shortcuts: ShortcutsViewModel = ShortcutsViewModel(),
        localModelLoadingStatus: LocalModelLoadingStatus? = nil
    ) {
        _providerSettings = StateObject(wrappedValue: providerSettings)
        _shortcuts = StateObject(wrappedValue: shortcuts)
        self.localModelLoadingStatus = localModelLoadingStatus
    }

    init(providerSettings: LLMProviderSettingsViewModel, shortcuts: ShortcutsViewModel,
         localModelLoadingStatus: LocalModelLoadingStatus? = nil, initialSection: Section) {
        self.init(providerSettings: providerSettings, shortcuts: shortcuts,
                  localModelLoadingStatus: localModelLoadingStatus)
        _selection = State(initialValue: initialSection)
    }

    public var body: some View {
        Group {
            if isLoaded { settingsTabs }
            else {
                ProgressView("正在加载设置…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("vox.settings.loading")
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 380, idealHeight: 420)
        .accessibilityIdentifier("vox.settings")
        .task {
            await providerSettings.load()
            await shortcuts.load()
            isLoaded = true
        }
        .onReceive(NotificationCenter.default.publisher(for: PreferencesNotification.hotkeysDidChange)) { _ in
            Task { await shortcuts.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PreferencesNotification.llmProviderDidChange)) { _ in
            Task { await providerSettings.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PreferencesNotification.llmAnalysisSettingsDidChange)) { _ in
            Task { await providerSettings.load() }
        }
    }

    private var settingsTabs: some View {
        TabView(selection: $selection) {
            MacOSShortcutSettingsPane(viewModel: shortcuts)
                .tag(Section.shortcuts)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            MacOSTextSettingsPane(viewModel: providerSettings, localModelLoadingStatus: localModelLoadingStatus)
                .tag(Section.text)
                .tabItem { Label("语音与文本", systemImage: "waveform") }
        }
    }
}

@MainActor
struct MacOSShortcutSettingsPane: View {
    @ObservedObject var viewModel: ShortcutsViewModel

    var quickRecordBinding: Binding<FunctionKey> {
        Binding(get: { viewModel.quickRecordKey },
                set: { key in Task { await viewModel.updateQuickRecordKey(key) } })
    }

    var panelBinding: Binding<FunctionKey> {
        Binding(get: { viewModel.showPanelKey },
                set: { key in Task { await viewModel.updateShowPanelKey(key) } })
    }

    var body: some View {
        Form {
            Section {
                Picker("快捷录音", selection: quickRecordBinding) {
                    ForEach(FunctionKey.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("vox.settings.quickRecordKey")
                Text("按住开始说话，松开后处理并粘贴到当前应用。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("录音") }
            Section {
                Picker("显示录音面板", selection: panelBinding) {
                    ForEach(FunctionKey.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("vox.settings.showPanelKey")
                Text("保留旧版浮动录音面板的快捷入口。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("兼容入口") }
            if viewModel.hasConflict {
                Label("两个操作使用了同一按键，请选择不同的快捷键。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("vox.settings.hotkeyConflict")
            }
            Button("重置快捷键") { Task { await viewModel.resetToDefaults() } }
                .accessibilityIdentifier("vox.settings.resetHotkeys")
        }
        .formStyle(.grouped)
    }
}

@MainActor
struct MacOSTextSettingsPane: View {
    @ObservedObject var viewModel: LLMProviderSettingsViewModel
    let localModelLoadingStatus: LocalModelLoadingStatus?

    var providerBinding: Binding<LLMProviderSelection> {
        Binding(get: { viewModel.selectedProvider },
                set: { provider in Task { await viewModel.updateProvider(provider) } })
    }

    var skipAnalysisBinding: Binding<Bool> {
        Binding(get: { viewModel.skipContentAnalysis },
                set: { skip in Task { await viewModel.updateSkipContentAnalysis(skip) } })
    }

    var body: some View {
        Form {
            Section {
                Picker("精炼服务商", selection: providerBinding) {
                    ForEach(LLMProviderSelection.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("vox.settings.llmProvider")
                Text("只影响文本精炼，不切换语音识别引擎。云端服务会接收需要精炼的文本。")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("跳过意图与语气分析", isOn: skipAnalysisBinding)
                .accessibilityIdentifier("vox.settings.skipAnalysis")
                Text("仅跳过前置分析，仍会执行文本精炼。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("文本精炼") }
            if let status = localModelLoadingStatus {
                MacOSLocalModelSettingsSection(status: status)
            }
            Section {
                Text("密钥与部署名仍由本机配置管理。已有历史数据会保留，不因移除主窗口而删除。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("配置与数据") }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct MacOSLocalModelSettingsSection: View {
    @ObservedObject var status: LocalModelLoadingStatus
    var body: some View {
        Section("本地语音模型") {
            Text(status.statusText)
            if let progress = status.downloadProgress { ProgressView(value: progress) }
        }
    }
}
#endif
