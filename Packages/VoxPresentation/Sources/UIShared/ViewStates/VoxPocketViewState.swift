import Foundation
import Combine
import CoreModels

/// VoxPocket view state protocol.
@MainActor
public protocol VoxPocketViewState: ObservableObject {

    associatedtype Editor: EditorViewState

    /// Editor state used by the VoxPocket view.
    var editorState: Editor { get }

    /// Current recorder status.
    var recorderStatus: RecorderStatus { get }

    /// Whether the raw transcript sheet is shown.
    var showRawSheet: Bool { get set }
}
