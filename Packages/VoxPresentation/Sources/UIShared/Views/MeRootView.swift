import SwiftUI
import Preferences

struct MeRootView: View {
    let status: RecorderStatus

    init(status: RecorderStatus = .idle) {
        self.status = status
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileCard()
                BehaviorCard()
#if os(macOS)
                ShortcutsCard()
#endif
                PrivacyCard()
                DiagnosticsCard()
                AboutCard()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(BackgroundAtmosphere(status: status))
    }
}

private enum MePalette {
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let divider = Color.primary.opacity(0.12)
    static let cardBorder = Color.primary.opacity(0.08)
}

struct ProfileCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Circle()
                    .fill(LinearGradient(colors: [Color.orange, Color.pink], startPoint: .top, endPoint: .bottom))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text("TP")
                            .font(.custom("Avenir Next", size: 18).weight(.bold))
                            .foregroundColor(.white)
                    )
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tianpei Li")
                        .font(.custom("Avenir Next", size: 18).weight(.semibold))
                        .foregroundColor(MePalette.primaryText)
                    Text("Pro Plan · Active")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(MePalette.secondaryText)
                }
                Spacer()
            }

            Divider().overlay(MePalette.divider)

            ProviderRow(provider: "ChatGPT", status: "Connected")
            ProviderRow(provider: "Claude", status: "Not linked")
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
                .font(.custom("Avenir Next", size: 14).weight(.semibold))
                .foregroundColor(MePalette.primaryText)
            Spacer()
            Text(status)
                .font(.custom("Avenir Next", size: 12))
                .foregroundColor(MePalette.secondaryText)
        }
    }
}

struct BehaviorCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Behavior")
                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                .foregroundColor(MePalette.primaryText)

            SettingRow(title: "Auto-stop silence", value: "2s")
            SettingRow(title: "VAD Advanced", value: "Off")
            SettingRow(title: "Auto-save", value: "On")
            SettingRow(title: "Streaming", value: "Off")
        }
        .modifier(CardStyle())
    }
}

struct PrivacyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Privacy & Data")
                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                .foregroundColor(MePalette.primaryText)

            SettingRow(title: "Data retention", value: "30 days")
            SettingRow(title: "Export data", value: "Ready")
            SettingRow(title: "Clear history", value: "Danger")
        }
        .modifier(CardStyle())
    }
}

struct DiagnosticsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diagnostics")
                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                .foregroundColor(MePalette.primaryText)

            SettingRow(title: "Logger level", value: "Verbose")
            SettingRow(title: "Share logs", value: "Tap")
        }
        .modifier(CardStyle())
    }
}

#if os(macOS)
struct ShortcutsCard: View {
    @StateObject private var viewModel = ShortcutsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shortcuts")
                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                .foregroundColor(MePalette.primaryText)

            ShortcutPickerRow(
                title: "Show Panel",
                selection: showPanelBinding
            )
            ShortcutPickerRow(
                title: "Quick Recording (press/release)",
                selection: quickRecordBinding
            )

            if viewModel.hasConflict {
                Text("Conflict: both actions use the same key")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.orange)
            }

            Button("Reset Hotkeys") {
                Task { await viewModel.resetToDefaults() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MePalette.primaryText.opacity(0.16))
            .foregroundColor(MePalette.primaryText)
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
                .font(.custom("Avenir Next", size: 13).weight(.medium))
                .foregroundColor(MePalette.primaryText)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(FunctionKey.allCases, id: \.self) { key in
                    Text(key.label).tag(key)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(MePalette.primaryText)
        }
    }
}

#endif

struct AboutCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About")
                .font(.custom("Avenir Next", size: 16).weight(.semibold))
                .foregroundColor(MePalette.primaryText)

            SettingRow(title: "Version", value: "0.1.0")
            SettingRow(title: "Privacy policy", value: "View")
            SettingRow(title: "Feedback", value: "Send")
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
                .font(.custom("Avenir Next", size: 13).weight(.medium))
                .foregroundColor(MePalette.primaryText)
            Spacer()
            Text(value)
                .font(.custom("Avenir Next", size: 12))
                .foregroundColor(MePalette.secondaryText)
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
                    .stroke(MePalette.cardBorder, lineWidth: 1)
            )
    }
}

#Preview {
    ZStack {
        BackgroundAtmosphere(status: .idle)
        MeRootView(status: .idle)
    }
}
