#if os(macOS)
import SwiftUI
import UIShared
import PlatformAdapters

/// 完整面板视图
///
/// 包装 VoxPocketView，用于浮动面板窗口。
public struct FullPanelView<VM: VoxPocketViewState>: View {
    @ObservedObject var viewModel: VM
    @StateObject private var snackbarService = DefaultSnackbarService()

    public init(viewModel: VM) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VoxPocketView(
            viewModel: viewModel,
            onCopyRefined: { text in
                guard !text.isEmpty else { return }
                MacOSClipboardService.shared.copy(text)
                snackbarService.showSuccess("已复制精炼文本")
            },
            onCopyRaw: { text in
                guard !text.isEmpty else { return }
                MacOSClipboardService.shared.copy(text)
                snackbarService.showSuccess("已复制原始转写")
            }
        )
            .frame(minWidth: 560, minHeight: 360)
            .snackbarOverlay(service: snackbarService)
    }
}
#endif
