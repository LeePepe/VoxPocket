#if os(macOS)
import SwiftUI
import UIShared
import PlatformAdapters

/// 完整面板视图
///
/// 包装 HomeRecorderView，用于浮动面板窗口。
public struct FullPanelView<VM: RootViewState>: View {
    @ObservedObject var viewModel: VM
    @StateObject private var snackbarService = DefaultSnackbarService()

    public init(viewModel: VM) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HomeRecorderView(
            viewModel: viewModel.editorState,
            recorderStatus: viewModel.recorderStatus,
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
            .onAppear {
                // 注入 snackbar，使录音被阻止时（如模型未就绪）能显示提示
                (viewModel.editorState as? EditorViewModel)?.snackbarService = snackbarService
            }
    }
}
#endif
