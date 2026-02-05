import SwiftUI

public struct VoxPocketView<VM: VoxPocketViewState>: View {
    @ObservedObject var viewModel: VM

    public init(viewModel: VM) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HomeRecorderView(
            viewModel: viewModel.editorState,
            recorderStatus: viewModel.recorderStatus,
            onToggleSidebar: nil,
            onShowRawSheet: {
                viewModel.showRawSheet = true
            }
        )
        .sheet(isPresented: $viewModel.showRawSheet) {
            RawTranscriptView(
                rawText: viewModel.editorState.liveTranscription,
                status: viewModel.recorderStatus
            )
        }
    }
}

#Preview {
    VoxPocketView(
        viewModel: VoxPocketViewModel(
            editorState: MockEditorViewModel()
        )
    )
}
