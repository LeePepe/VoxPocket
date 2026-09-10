import SwiftUI

/// content 保持惰性，配置就绪前不会构造依赖 ServiceContainer 的视图。
@MainActor
struct AppStartupView<Content: View>: View {
    @ObservedObject private var startup: AppStartup
    private let content: () -> Content

    init(startup: AppStartup, @ViewBuilder content: @escaping () -> Content) {
        self.startup = startup
        self.content = content
    }

    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(startup: .shared, content: content)
    }

    var body: some View {
        Group {
            switch startup.phase {
            case .loading:
                ProgressView {
                    Text("正在加载本机配置…").foregroundStyle(.primary)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("vox.startup.loading")
            case .ready:
                content()
            case .failed:
                ContentUnavailableView {
                    Label("无法加载模型配置", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("请检查本机 config.private.json 的格式和访问权限，然后重新启动 VoxPocket。")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("vox.startup.error")
            }
        }
        .task { _ = await startup.prepare() }
    }
}
