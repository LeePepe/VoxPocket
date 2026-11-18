import Foundation
import Combine
import CoreModels

@MainActor
public protocol VoxWorkspaceViewState: AnyObject, ObservableObject {
    var captureState: CaptureSessionState { get }
    var selectedCaptureMode: CaptureMode { get set }
    var recordingElapsedSeconds: Int { get }
    var audioLevel: Float { get set }
    var lastCopiedBannerText: String? { get }
    var playingCaptureID: UUID? { get set }
    var searchQuery: String { get set }
    var selectedTodoFilter: TodoStatusFilter { get set }
    var selectedPriorityFilter: TodoPriority? { get set }
    var selectedTagFilter: String? { get set }
    var selectedProjectFilter: String? { get set }
    var hasActiveTodoFilters: Bool { get }
    var sortOrder: WorkspaceSortOrder { get set }
    var selectedSidebarSection: WorkspaceSidebarSection { get set }
    var activePage: WorkspacePage { get set }
    var expandedTodoID: UUID? { get set }
    var selectedTodoID: UUID? { get set }
    var selectedCaptureID: UUID? { get set }
    var filteredTodos: [VoiceTodo] { get }
    var filteredCaptures: [VoiceCapture] { get }
}
