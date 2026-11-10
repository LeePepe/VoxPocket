#if os(macOS)
import AppKit
import Carbon
import SwiftUI
import Preferences

/// 原生设置复用「我的」的偏好模型，不创建编辑器、会话或录音服务。
@MainActor
public struct MacOSSettingsView: View {
    @StateObject private var providerSettings: LLMProviderSettingsViewModel
    @StateObject private var shortcuts: ShortcutsViewModel
    @StateObject private var productTelemetry: ProductTelemetrySettingsViewModel
    private let observeProductTelemetryControl: (@MainActor (ProductTelemetrySettingsViewModel) -> Void)?
    private let loadProviderSettings: (@MainActor (LLMProviderSettingsViewModel) async -> Void)?
    private let loadShortcuts: (@MainActor (ShortcutsViewModel) async -> Void)?
    @State private var providerSettingsLoaded = false
    @State private var shortcutsLoaded = false
    @State private var selection: Section = .shortcuts
    let localModelLoadingStatus: LocalModelLoadingStatus?
    enum Section: Hashable { case shortcuts, text, privacy }

    public init(
        providerSettings: LLMProviderSettingsViewModel = LLMProviderSettingsViewModel(),
        shortcuts: ShortcutsViewModel = ShortcutsViewModel(),
        productTelemetry: ProductTelemetrySettingsViewModel = ProductTelemetrySettingsViewModel(),
        localModelLoadingStatus: LocalModelLoadingStatus? = nil
    ) {
        _providerSettings = StateObject(wrappedValue: providerSettings)
        _shortcuts = StateObject(wrappedValue: shortcuts)
        _productTelemetry = StateObject(wrappedValue: productTelemetry)
        observeProductTelemetryControl = nil
        loadProviderSettings = nil
        loadShortcuts = nil
        self.localModelLoadingStatus = localModelLoadingStatus
    }

    init(providerSettings: LLMProviderSettingsViewModel, shortcuts: ShortcutsViewModel,
         productTelemetry: ProductTelemetrySettingsViewModel = ProductTelemetrySettingsViewModel(),
         localModelLoadingStatus: LocalModelLoadingStatus? = nil, initialSection: Section,
         observeProductTelemetryControl: (@MainActor (ProductTelemetrySettingsViewModel) -> Void)? = nil,
         loadProviderSettings: (@MainActor (LLMProviderSettingsViewModel) async -> Void)? = nil,
         loadShortcuts: (@MainActor (ShortcutsViewModel) async -> Void)? = nil) {
        _providerSettings = StateObject(wrappedValue: providerSettings)
        _shortcuts = StateObject(wrappedValue: shortcuts)
        _productTelemetry = StateObject(wrappedValue: productTelemetry)
        self.localModelLoadingStatus = localModelLoadingStatus
        self.observeProductTelemetryControl = observeProductTelemetryControl
        self.loadProviderSettings = loadProviderSettings
        self.loadShortcuts = loadShortcuts
        _selection = State(initialValue: initialSection)
    }

    public var body: some View {
        settingsTabs
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 680)
        .accessibilityIdentifier("vox.settings")
        .task {
            if let loadProviderSettings {
                await loadProviderSettings(providerSettings)
            } else {
                await providerSettings.load()
            }
            providerSettingsLoaded = true
        }
        .task {
            if let loadShortcuts {
                await loadShortcuts(shortcuts)
            } else {
                await shortcuts.load()
            }
            shortcutsLoaded = true
        }
        .task {
            await productTelemetry.load()
            observeProductTelemetryControl?(productTelemetry)
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
            loadedPane(isLoaded: shortcutsLoaded) {
                MacOSShortcutSettingsPane(viewModel: shortcuts)
            }
                .tag(Section.shortcuts)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            loadedPane(isLoaded: providerSettingsLoaded) {
                MacOSTextSettingsPane(
                    viewModel: providerSettings,
                    localModelLoadingStatus: localModelLoadingStatus
                )
            }
                .tag(Section.text)
                .tabItem { Label("语音与文本", systemImage: "waveform") }
            productTelemetrySettings
                .tag(Section.privacy)
                .tabItem { Label("隐私", systemImage: "hand.raised") }
        }
    }

    @ViewBuilder
    private func loadedPane<Content: View>(
        isLoaded: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if isLoaded {
            content()
        } else {
            ProgressView("正在加载设置…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("vox.settings.loading")
        }
    }

    var productTelemetrySettings: some View {
        ProductTelemetrySettingsView(viewModel: productTelemetry)
            .onChange(of: productTelemetry.isSendingUsageData) {
                observeProductTelemetryControl?(productTelemetry)
            }
    }
}

@MainActor
public struct ProductTelemetrySettingsView: View {
    @ObservedObject private var viewModel: ProductTelemetrySettingsViewModel

    public init(viewModel: ProductTelemetrySettingsViewModel) {
        self.viewModel = viewModel
    }

    var consentBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isSendingUsageData },
            set: { value in Task { await viewModel.setSendingUsageData(value) } }
        )
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Send usage data", isOn: consentBinding)
                    .disabled(!viewModel.isLoaded)
                    .accessibilityIdentifier("vox.settings.sendUsageData")
                Text("发送不含录音、转写文本或精炼文本的使用情况事件。你可以随时关闭。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("产品改进")
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
struct MacOSShortcutSettingsPane: View {
    @ObservedObject var viewModel: ShortcutsViewModel
    @State private var recordingTarget: RecordingTarget?
    @State private var eventMonitor: Any?
    @State private var sawFnPress = false

    enum RecordingTarget: Equatable {
        case directToText
        case voiceToTodo
    }

    var body: some View {
        Form {
            Section {
                shortcutRecorderRow(
                    title: "录音到剪贴板",
                    currentLabel: viewModel.directToTextDisplayName,
                    target: .directToText,
                    buttonIdentifier: "vox.settings.recordDirectToTextHotkey"
                )
                Text("按住开始说话，松开后精炼文本并复制/粘贴到当前应用。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("录音到剪贴板") }
            Section {
                shortcutRecorderRow(
                    title: "录音到 Todo",
                    currentLabel: viewModel.voiceToTodoDisplayName,
                    target: .voiceToTodo,
                    buttonIdentifier: "vox.settings.recordVoiceToTodoHotkey"
                )
                Text("按住开始说话，松开后提取并创建待办事项。")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("录音到 Todo") }
            if viewModel.hasConflict {
                Label("两个操作使用了同一按键，请选择不同的快捷键。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("vox.settings.hotkeyConflict")
            }
            Button("重置快捷键") { Task { await viewModel.resetToDefaults() } }
                .accessibilityIdentifier("vox.settings.resetHotkeys")
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private func shortcutRecorderRow(
        title: String,
        currentLabel: String,
        target: RecordingTarget,
        buttonIdentifier: String
    ) -> some View {
        let isRecording = recordingTarget == target
        return HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(.primary)
            Text(isRecording ? "请按下按键或组合键（Esc 取消）…" : currentLabel)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    (isRecording ? Color.accentColor : Color.secondary).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            Spacer()
            Button(isRecording ? "取消录制" : "录制快捷键") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording(for: target)
                }
            }
            .accessibilityIdentifier(buttonIdentifier)
        }
    }

    func startRecording(for target: RecordingTarget) {
        stopRecording()
        recordingTarget = target
        sawFnPress = false
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if handleRecordedEvent(event) {
                return nil
            }
            return event
        }
    }

    func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        recordingTarget = nil
        sawFnPress = false
    }

    enum RecordedEventDisposition: Equatable {
        case ignore
        case consumePending(sawFnPress: Bool)
        case cancel
        case commit(keyCode: UInt16, modifiers: UInt)
    }

    static func classifyRecordedEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        sawFnPress: Bool
    ) -> RecordedEventDisposition {
        if type == .flagsChanged {
            guard keyCode == UInt16(kVK_Function) else { return .ignore }
            if modifierFlags.contains(.function) {
                return .consumePending(sawFnPress: true)
            }
            return sawFnPress
                ? .commit(keyCode: UInt16(kVK_Function), modifiers: 0)
                : .consumePending(sawFnPress: false)
        }

        guard type == .keyDown else { return .ignore }
        let modifiers = ShortcutsViewModel.carbonModifiers(from: modifierFlags)
        if keyCode == UInt16(kVK_Escape) && modifiers == 0 {
            return .cancel
        }
        if modifierOnlyKeyCodes.contains(keyCode) {
            return .consumePending(sawFnPress: sawFnPress)
        }
        return .commit(keyCode: keyCode, modifiers: modifiers)
    }

    @discardableResult
    func handleRecordedEvent(_ event: NSEvent) -> Bool {
        guard let target = recordingTarget else { return false }
        switch Self.classifyRecordedEvent(
            type: event.type,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            sawFnPress: sawFnPress
        ) {
        case .ignore:
            return false
        case .consumePending(let nextSawFn):
            sawFnPress = nextSawFn
            return true
        case .cancel:
            stopRecording()
            return true
        case .commit(let keyCode, let modifiers):
            applyRecordedHotkey(target: target, keyCode: keyCode, modifiers: modifiers)
            return true
        }
    }

    private func applyRecordedHotkey(target: RecordingTarget, keyCode: UInt16, modifiers: UInt) {
        stopRecording()
        Task {
            switch target {
            case .directToText:
                await viewModel.updateDirectToTextHotkey(keyCode: keyCode, modifiers: modifiers)
            case .voiceToTodo:
                await viewModel.updateVoiceToTodoHotkey(keyCode: keyCode, modifiers: modifiers)
            }
        }
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock),
        UInt16(kVK_Function)
    ]
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
