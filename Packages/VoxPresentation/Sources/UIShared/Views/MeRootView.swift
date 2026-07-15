import SwiftUI
import Preferences

struct MeRootView: View {
    let status: RecorderStatus
    var onDeleteAllHistory: (() -> Void)?
    var localModelLoadingStatus: LocalModelLoadingStatus?

    init(
        status: RecorderStatus = .idle,
        onDeleteAllHistory: (() -> Void)? = nil,
        localModelLoadingStatus: LocalModelLoadingStatus? = nil
    ) {
        self.status = status
        self.onDeleteAllHistory = onDeleteAllHistory
        self.localModelLoadingStatus = localModelLoadingStatus
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileCard()
                BehaviorCard()
                LLMProviderCard()
                if let loadingStatus = localModelLoadingStatus, loadingStatus.state != .idle {
                    LocalModelLoadingCard(status: loadingStatus)
                }
#if os(macOS)
                ShortcutsCard()
#endif
                PrivacyCard(onDeleteAllHistory: onDeleteAllHistory)
                DiagnosticsCard()
                AboutCard()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(BackgroundAtmosphere(status: status))
    }
}

struct ProfileCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Circle()
                    .fill(LinearGradient(colors: [Color.orange, Color.pink], startPoint: .top, endPoint: .bottom))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text("VP")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 6) {
                    Text("VoxPocket 用户")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.primary)
                    Text("本地账户")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(Color.secondary)
                }
                Spacer()
            }

            Divider().overlay(Color.primary.opacity(0.12))

            ProviderRow(provider: "ChatGPT", status: "未连接")
            ProviderRow(provider: "Claude", status: "未连接")
        }
        .modifier(CardStyle())
    }
}

struct ProviderRow: View {
    let provider: String
    let status: String

    var body: some View {
        HStack {
            Text(provider)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(Color.primary)
            Spacer()
            Text(status)
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(Color.secondary)
        }
    }
}

struct BehaviorCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("行为")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Color.primary)

            SettingRow(title: "静音自动停止", value: "2s")
            SettingRow(title: "VAD Advanced", value: "Off")
            SettingRow(title: "自动保存", value: "On")
            SettingRow(title: "流式", value: "Off")
        }
        .modifier(CardStyle())
    }
}

struct LLMProviderCard: View {
    @StateObject private var viewModel = LLMProviderSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("模型服务")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Color.primary)

            HStack {
                Text("服务商")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(Color.primary)
                Spacer()
                Picker("", selection: providerBinding) {
                    ForEach(LLMProviderSelection.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.accentColor)
            }

            Divider().overlay(Color.primary.opacity(0.12))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip intent analysis")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(Color.primary)
                    Text("直接使用默认改写，跳过意图/语气前置分析")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(Color.secondary)
                }
                Spacer()
                Toggle("", isOn: skipAnalysisBinding)
                    .labelsHidden()
                    .tint(Color.accentColor)
            }
        }
        .modifier(CardStyle())
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private var providerBinding: Binding<LLMProviderSelection> {
        Binding(
            get: { viewModel.selectedProvider },
            set: { newValue in
                Task { await viewModel.updateProvider(newValue) }
            }
        )
    }

    private var skipAnalysisBinding: Binding<Bool> {
        Binding(
            get: { viewModel.skipContentAnalysis },
            set: { newValue in
                Task { await viewModel.updateSkipContentAnalysis(newValue) }
            }
        )
    }
}

struct PrivacyCard: View {
    var onDeleteAllHistory: (() -> Void)?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("隐私与数据")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Color.primary)

            SettingRow(title: "数据保留", value: "30 days")
            SettingRow(title: "导出数据", value: "Ready")

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("清除历史")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(.red)
                    Spacer()
                    Text("删除全部")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.red.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .confirmationDialog("确认删除所有历史记录？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("删除全部", role: .destructive) {
                    onDeleteAllHistory?()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作不可撤销，所有会话记录将被永久删除。")
            }
        }
        .modifier(CardStyle())
    }
}

struct DiagnosticsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("诊断")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Color.primary)

            SettingRow(title: "日志级别", value: "Verbose")
            SettingRow(title: "分享日志", value: "Tap")
        }
        .modifier(CardStyle())
    }
}

#if os(macOS)
struct ShortcutsCard: View {
    @StateObject private var viewModel = ShortcutsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷键")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Color.primary)

            ShortcutPickerRow(
                title: "显示面板",
                selection: showPanelBinding
            )
            ShortcutPickerRow(
                title: "Quick Recording (press/release)",
                selection: quickRecordBinding
            )

            if viewModel.hasConflict {
                Text("Conflict: both actions use the same key")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.orange)
            }

            Button("重置快捷键") {
                Task { await viewModel.resetToDefaults() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
        }
        .modifier(CardStyle())
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private var showPanelBinding: Binding<FunctionKey> {
        Binding(
            get: { viewModel.showPanelKey },
            set: { newValue in
                Task { await viewModel.updateShowPanelKey(newValue) }
            }
        )
    }

    private var quickRecordBinding: Binding<FunctionKey> {
        Binding(
            get: { viewModel.quickRecordKey },
            set: { newValue in
                Task { await viewModel.updateQuickRecordKey(newValue) }
            }
        )
    }
}

struct ShortcutPickerRow: View {
    let title: String
    @Binding var selection: FunctionKey

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(Color.primary)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(FunctionKey.allCases, id: \.self) { key in
                    Text(key.label).tag(key)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.accentColor)
        }
    }
}

#endif

struct AboutCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("关于")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(Color.primary)

            SettingRow(title: "版本", value: "0.1.0")
            SettingRow(title: "隐私政策", value: "View")
            SettingRow(title: "反馈", value: "Send")
        }
        .modifier(CardStyle())
    }
}

struct SettingRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(Color.primary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(Color.secondary)
        }
    }
}

struct LocalModelLoadingCard: View {
    @ObservedObject var status: LocalModelLoadingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("本地模型")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Color.primary)
                Spacer()
                statusBadge
            }

            if let progress = status.downloadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(status.statusText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(Color.secondary)
                    ProgressView(value: progress)
                        .tint(.blue)
                }
            } else {
                HStack(spacing: 8) {
                    if status.isInProgress {
                        ProgressView()
                            .scaleEffect(0.75)
                    }
                    Text(status.statusText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .modifier(CardStyle())
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status.state {
        case .downloading, .loading:
            Text("加载中")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12), in: Capsule())
        case .ready:
            Text("就绪")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12), in: Capsule())
        case .failed:
            Text("失败")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.12), in: Capsule())
        case .idle:
            EmptyView()
        }
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

#Preview {
    ZStack {
        BackgroundAtmosphere(status: .idle)
        MeRootView(status: .idle)
    }
}
