#if os(macOS)
import SwiftUI
import UIShared

/// 完整面板视图
///
/// 包装 VoxPocketView，用于浮动面板窗口。
public struct FullPanelView<VM: VoxPocketViewState>: View {
    @ObservedObject var viewModel: VM

    public init(viewModel: VM) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VoxPocketView(viewModel: viewModel)
            .frame(minWidth: 600, minHeight: 400)
    }
}
#endif
