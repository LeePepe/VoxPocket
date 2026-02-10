import SwiftUI

public struct VoxPocketView<VM: VoxPocketViewState>: View {
    @ObservedObject var viewModel: VM
    let onCopyRefined: (String) -> Void
    let onCopyRaw: (String) -> Void

    public init(
        viewModel: VM,
        onCopyRefined: @escaping (String) -> Void = { _ in },
        onCopyRaw: @escaping (String) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onCopyRefined = onCopyRefined
        self.onCopyRaw = onCopyRaw
    }

    public var body: some View {
        HomeRecorderView(
            viewModel: viewModel.editorState,
            recorderStatus: viewModel.recorderStatus,
            onCopyRefined: onCopyRefined,
            onCopyRaw: onCopyRaw
        )
        .sheet(isPresented: $viewModel.showRawSheet) {
            let rawText = viewModel.editorState.isRecording
                ? viewModel.editorState.liveTranscription
                : viewModel.editorState.rawTranscription
            RawTranscriptView(
                rawText: rawText,
                status: viewModel.recorderStatus,
                canCopyRaw: !rawText.isEmpty,
                onCopyRaw: {
                    onCopyRaw(rawText)
                }
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
