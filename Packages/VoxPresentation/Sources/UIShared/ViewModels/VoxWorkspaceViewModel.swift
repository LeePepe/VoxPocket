import Foundation
import Combine
import CoreModels
import UseCases

@MainActor
public final class VoxWorkspaceViewModel: ObservableObject, VoxWorkspaceViewState {
    private let useCase: any VoiceCaptureAndTodoUseCase
    private var reloadTask: Task<Void, Never>?

    @Published public private(set) var captures: [VoiceCapture] = []
    @Published public private(set) var todos: [VoiceTodo] = []
    @Published public private(set) var projectBindings: [ProjectBinding]
    @Published public private(set) var runnerTemplates: [AIRunnerTemplate]
    @Published public private(set) var captureState: CaptureSessionState = .idle
    @Published public var selectedCaptureMode: CaptureMode = .text
    @Published public private(set) var recordingElapsedSeconds = 0
    @Published public var audioLevel: Float = 0
    @Published public private(set) var lastCopiedBannerText: String?
    @Published public var playingCaptureID: UUID?
    @Published public var searchQuery = ""
    @Published public var selectedTodoFilter: TodoStatusFilter = .all
    @Published public var selectedProjectFilter: String?
    @Published public var sortOrder: WorkspaceSortOrder = .newestFirst
    @Published public var selectedSidebarSection: WorkspaceSidebarSection = .todoAll
    @Published public var selectedTodoID: UUID?
    @Published public var selectedCaptureID: UUID?

    public init(useCase: any VoiceCaptureAndTodoUseCase, projectBindings: [ProjectBinding] = [], runnerTemplates: [AIRunnerTemplate] = AIRunnerTemplate.defaultPresets) {
        self.useCase = useCase; self.projectBindings = projectBindings; self.runnerTemplates = runnerTemplates
        reloadTask = Task { [weak self] in await self?.reload() }
    }

    public var filteredTodos: [VoiceTodo] { todos.filter { todo in matches(todo) }.sorted { ordered($0.updatedAt, $1.updatedAt) } }
    public var filteredCaptures: [VoiceCapture] { captures.filter { capture in searchQuery.isEmpty || capture.rawTranscript.localizedCaseInsensitiveContains(searchQuery) || capture.refinedText.localizedCaseInsensitiveContains(searchQuery) }.sorted { ordered($0.updatedAt, $1.updatedAt) } }
    public var inboxCount: Int { count(.inbox) }
    public var runningCount: Int { count(.running) }
    public var doneCount: Int { count(.done) }
    public var failedCount: Int { count(.failed) }
    public var totalTodoCount: Int { todos.count }
    public var projectCounts: [String: Int] { Dictionary(grouping: todos.compactMap(\.projectKey), by: { $0 }).mapValues(\.count) }

    public func clearSearchPreservingFilters() { searchQuery = "" }
    public func startCapture(mode: CaptureMode) { selectedCaptureMode = mode; captureState = .recording(mode: mode); recordingElapsedSeconds = 0 }
    public func toggleCaptureModeDuringRecording() { guard case .recording = captureState else { return }; selectedCaptureMode = selectedCaptureMode == .text ? .todo : .text; captureState = .recording(mode: selectedCaptureMode) }
    public func cancelCapture() { captureState = .idle; recordingElapsedSeconds = 0; audioLevel = 0 }
    public func finishCapture() { captureState = .completed }

    public func convertCaptureToTodo(_ captureID: UUID) { perform { [weak self] in guard let self else { return }; _ = try await useCase.convertCaptureToTodo(captureID: captureID); await reload() } }
    public func retryCapture(_ captureID: UUID, mode: CaptureMode? = nil) { perform { [weak self] in guard let self else { return }; _ = try await useCase.retryCapture(id: captureID, targetMode: mode); await reload() } }
    public func runTodoWithAI(_ todoID: UUID, projectID: UUID?, runnerKind: AIRunnerKind? = nil) { perform { [weak self] in guard let self, let project = projectID.flatMap({ id in projectBindings.first(where: { $0.id == id }) }) ?? projectBindings.first else { return }; let template = runnerTemplates.first(where: { $0.kind == runnerKind }) ?? runnerTemplates.first(where: { $0.kind == project.defaultRunnerKind }) ?? AIRunnerTemplate.herdrDefault; _ = try await useCase.runTodoWithAI(todoID: todoID, project: project, template: template); await reload() } }
    public func saveTodoEdits(id: UUID, title: String, taskPrompt: String, projectKey: String?, runnerKind: AIRunnerKind? = nil) { perform { [weak self] in guard let self, let todo = todos.first(where: { $0.id == id }) else { return }; _ = try await useCase.updateTodo(todo.withEdits(title: title, taskPrompt: taskPrompt, projectKey: projectKey, assignedRunnerKind: runnerKind)); await reload() } }
    public func addProjectBinding(_ binding: ProjectBinding) { projectBindings.append(binding) }
    public func removeProjectBinding(id: UUID) { projectBindings.removeAll { $0.id == id } }
    public func updateRunnerTemplate(_ template: AIRunnerTemplate) { runnerTemplates.removeAll { $0.kind == template.kind }; runnerTemplates.append(template) }

    private func reload() async { do { captures = try await useCase.fetchCaptures(); todos = try await useCase.fetchTodos() } catch { } }
    private func perform(_ operation: @escaping () async throws -> Void) { Task { do { try await operation() } catch { captureState = .failed(stage: .ai, reason: error.localizedDescription) } } }
    private func count(_ state: TodoExecutionState) -> Int { todos.filter { $0.executionState == state }.count }
    private func matches(_ todo: VoiceTodo) -> Bool { (selectedTodoFilter == .all || todo.executionState.rawValue == selectedTodoFilter.rawValue) && (selectedProjectFilter == nil || todo.projectKey == selectedProjectFilter) && (searchQuery.isEmpty || todo.title.localizedCaseInsensitiveContains(searchQuery) || todo.taskPrompt.localizedCaseInsensitiveContains(searchQuery) || todo.rawTranscript.localizedCaseInsensitiveContains(searchQuery)) }
    private func ordered(_ lhs: Date, _ rhs: Date) -> Bool { sortOrder == .newestFirst ? lhs > rhs : lhs < rhs }
}
