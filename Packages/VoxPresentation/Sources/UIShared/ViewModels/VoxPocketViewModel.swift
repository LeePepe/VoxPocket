import Foundation
import Combine
import CoreModels

/// ViewModel for the VoxPocket view.
@MainActor
public final class VoxPocketViewModel<E: EditorViewState>: ObservableObject, VoxPocketViewState {

    public let editorState: E

    @Published public var recorderStatus: RecorderStatus = .idle
    @Published public var showRawSheet: Bool = false

    private var cancellables = Set<AnyCancellable>()

    public init(editorState: E) {
        self.editorState = editorState
        bindEditorState()
    }

    private func bindEditorState() {
        editorState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateRecorderStatus()
            }
            .store(in: &cancellables)
    }

    private func updateRecorderStatus() {
        if editorState.isRecording {
            recorderStatus = .listening
        } else if editorState.isRefining {
            recorderStatus = .refining
        } else if editorState.errorMessage != nil {
            recorderStatus = .error
        } else {
            recorderStatus = .idle
        }
    }
}
