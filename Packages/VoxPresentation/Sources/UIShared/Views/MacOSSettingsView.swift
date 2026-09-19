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
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 680)
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
        .onReceive(NotificationCenter.default.publisher(for: PreferencesNotification.stageModelsDidChange)) { _ in
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
    @State private var deploymentExpanded = false

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
            speechSection
            analysisSection
            refinementSection
            if let status = localModelLoadingStatus { MacOSLocalModelSettingsSection(status: status) }
            Section {
                Text("模型选择自动保存，下次录音生效，不改变正在处理的录音。密钥和服务地址仍由受保护的本机配置管理。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("配置与数据") }
        }
        .formStyle(.grouped)
        .task { deploymentExpanded = !viewModel.realtimeReady }
        .onChange(of: viewModel.speechModel) { _, model in
            if model == .realtime && !viewModel.realtimeReady { deploymentExpanded = true }
        }
    }

    private var speechSection: some View {
        Section {
                Picker("识别模型", selection: Binding(get: { viewModel.speechModel }, set: { model in
                    Task { await viewModel.updateSpeechModel(model) }
                })) {
                    Text("gpt-live-transcribe · 流式（默认）").tag(SpeechModelSelection.realtime)
                    Text("已配置的 Azure 模型 · 整段").tag(SpeechModelSelection.batch)
                    Text("Apple Speech · 系统识别").tag(SpeechModelSelection.appleSpeech)
                }
                .accessibilityIdentifier("vox.settings.speechModel")
                speechStatus
                if viewModel.speechModel == .realtime {
                    Text("边录音边发送音频；服务失败时回退整段转写。配置就绪不代表已通过真实音频验证。")
                        .font(.callout).foregroundStyle(.secondary)
                    DisclosureGroup("实时部署配置", isExpanded: $deploymentExpanded) {
                        HStack {
                            TextField("部署名", text: $viewModel.realtimeDeploymentDraft,
                                      prompt: Text(viewModel.availability.realtimeDeployment.isEmpty
                                                   ? "填写资源中的实时部署名" : viewModel.availability.realtimeDeployment))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("vox.settings.realtimeDeployment")
                            Button("保存") { Task { await viewModel.saveRealtimeDeployment() } }
                                .accessibilityIdentifier("vox.settings.saveRealtimeDeployment")
                        }
                        Text("部署名不一定等于模型名。留空使用本机配置；这里只保存部署名，不保存密钥。")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let message = viewModel.deploymentMessage {
                            Text(message).font(.caption)
                                .accessibilityIdentifier("vox.settings.deploymentMessage")
                        }
                    }
                } else if viewModel.speechModel == .batch {
                    Text("Apple Speech 提供预览；松手后上传整段音频获取终稿。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } header: { Text("1 · 语音识别") }
    }

    private var analysisSection: some View {
        Section {
                Toggle("跳过意图与语气分析", isOn: skipAnalysisBinding)
                    .accessibilityIdentifier("vox.settings.skipAnalysis")
                Picker("意图模型", selection: Binding(get: { viewModel.intentModel }, set: { model in
                    Task { await viewModel.updateIntentModel(model) }
                })) { analysisOptions }
                    .disabled(viewModel.skipContentAnalysis)
                    .accessibilityIdentifier("vox.settings.intentModel")
                Picker("语气模型", selection: Binding(get: { viewModel.toneModel }, set: { model in
                    Task { await viewModel.updateToneModel(model) }
                })) { analysisOptions }
                    .disabled(viewModel.skipContentAnalysis)
                    .accessibilityIdentifier("vox.settings.toneModel")
                Text("跳过可减少前置处理步骤，仍会执行文本精炼。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("2 · 内容分析") }
    }

    private var refinementSection: some View {
        Section {
                Picker("精炼模型", selection: providerBinding) {
                    Text("Apple Intelligence").tag(LLMProviderSelection.appleIntelligence)
                    Text(viewModel.cloudModelLabel).tag(LLMProviderSelection.azureFoundry)
                }
                .accessibilityIdentifier("vox.settings.llmProvider")
                Text("云端模型会接收对应阶段的文本。Apple Intelligence 需要设备支持并已启用。")
                    .font(.callout).foregroundStyle(.secondary)
                if !viewModel.availability.textConfigured &&
                    (viewModel.selectedProvider == .azureFoundry || (!viewModel.skipContentAnalysis &&
                     (viewModel.intentModel == .azureFoundry || viewModel.toneModel == .azureFoundry))) {
                    Label {
                        Text("意图、语气或精炼所选的云端模型尚未配置，请检查本机模型配置。")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    .font(.callout).foregroundStyle(.primary)
                }
            } header: { Text("3 · 文本精炼") }
    }

    private var analysisOptions: some View {
        Group {
            Text("Apple Intelligence").tag(TextModelSelection.appleIntelligence)
            Text(viewModel.cloudModelLabel).tag(TextModelSelection.azureFoundry)
        }
    }

    private var speechStatus: some View {
        Label {
            Text(viewModel.speechStatus).foregroundStyle(.primary)
        } icon: {
            Image(systemName: viewModel.hasSpeechWarning ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(viewModel.hasSpeechWarning ? Color.orange : Color.accentColor)
        }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((viewModel.hasSpeechWarning ? Color.orange : Color.accentColor).opacity(0.12), in: Capsule())
            .accessibilityIdentifier("vox.settings.speechStatus")
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
