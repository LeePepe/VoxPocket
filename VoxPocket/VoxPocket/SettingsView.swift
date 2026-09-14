#if os(macOS)
import SwiftUI
import UIShared

/// 只装配展示层设置及已有模型状态；不创建主编辑器或会话。
@MainActor
struct SettingsView: View {
    @State private var localModelLoadingStatus: LocalModelLoadingStatus?

    var body: some View {
        MacOSSettingsView(localModelLoadingStatus: localModelLoadingStatus)
            .task {
                if localModelLoadingStatus == nil,
                   let observable = ServiceContainer.shared.localModelLoadingObservable {
                    localModelLoadingStatus = LocalModelLoadingStatus(observable: observable)
                }
            }
    }
}
#endif
