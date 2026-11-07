import XCTest
import CoreModels
import UseCases
@testable import UIShared

final class VoxWorkspaceContractTests: XCTestCase {
    func testTodoExtractorBuildsBoundedTitleAndProjectMatch() async throws {
        let binding = ProjectBinding(projectKey: "VP", displayName: "VoxPocket", matchKeywords: ["voice"], localDirectoryPath: "/tmp")
        let draft = try await DefaultVoiceTodoExtractor().extractTodo(
            from: "Please improve the voice capture experience with a very long context that should be shortened for the title.",
            refinedText: "",
            availableProjects: [binding]
        )
        XCTAssertLessThanOrEqual(draft.title.count, 60)
        XCTAssertEqual(draft.matchedProjectKey, "VP")
        XCTAssertTrue(draft.taskPrompt.contains("Goal"))
    }

    @MainActor
    func testDeepLinksPreserveLegacyAndSupportCaptureModes() async {
        let router = DefaultDeepLinkRouter()
        XCTAssertEqual(router.resolve(URL(string: "voxpocket://quickRecord")!), .startRecording)
        XCTAssertEqual(router.resolve(URL(string: "voxpocket://quickRecord?mode=todo")!), .startRecordingInMode(.todo))
        XCTAssertEqual(router.resolve(URL(string: "voxpocket://stopRecording")!), .stopRecording)

        let rootVM = RootViewModel(sessionListState: MockSessionListViewModel(), editorState: MockEditorViewModel(), deepLinkRouter: router)
        let useCase = FakeCaptureAndTodoUseCase()
        let workspaceVM = VoxWorkspaceViewModel(
            useCase: useCase,
            captureRecorder: { mode in
                (rawTranscript: "Voice todo via deep link", refinedText: "Refined todo", localAudioFileName: nil, durationSeconds: 2)
            }
        )
        rootVM.onStartRecordingInMode = { mode in
            workspaceVM.startCapture(mode: mode)
        }
        rootVM.onStopRecordingInMode = { _ in
            await workspaceVM.completeCapture()
        }
        await rootVM.handleDeepLinkAction(.startRecordingInMode(.todo))
        XCTAssertEqual(rootVM.lastRequestedCaptureMode, .todo)
        XCTAssertTrue(workspaceVM.isRecordingActive)
        await rootVM.handleDeepLinkAction(.stopRecording)
        XCTAssertFalse(workspaceVM.isRecordingActive)
        XCTAssertEqual(workspaceVM.todos.count, 1)
    }

    private final class FakeCaptureAndTodoUseCase: VoiceCaptureAndTodoUseCase, @unchecked Sendable {
        var storedCaptures: [VoiceCapture] = []
        var storedTodos: [VoiceTodo] = []
        func recordCompletedCapture(mode: CaptureMode, rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> (capture: VoiceCapture, todo: VoiceTodo?) {
            let capture = VoiceCapture(mode: mode, rawTranscript: rawTranscript, refinedText: refinedText, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, state: .completed)
            storedCaptures.append(capture)
            let todo = mode == .todo ? VoiceTodo(title: rawTranscript, taskPrompt: refinedText, rawTranscript: rawTranscript, projectKey: "VP", sourceCaptureID: capture.id) : nil
            if let todo { storedTodos.append(todo) }
            return (capture, todo)
        }
        func recordFailedCapture(mode: CaptureMode, stage: FailureStage, reason: String, rawTranscript: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> VoiceCapture {
            VoiceCapture(mode: mode, rawTranscript: rawTranscript, state: .failed(stage: stage, reason: reason))
        }
        func retryCapture(id: UUID, targetMode: CaptureMode?) async throws -> (capture: VoiceCapture, todo: VoiceTodo?) {
            (storedCaptures[0], storedTodos.first)
        }
        func convertCaptureToTodo(captureID: UUID) async throws -> VoiceTodo { storedTodos[0] }
        func updateTodo(_ todo: VoiceTodo) async throws -> VoiceTodo { todo }
        func runTodoWithAI(todoID: UUID, project: ProjectBinding, template: AIRunnerTemplate) async throws -> VoiceTodo { storedTodos[0] }
        func markTodoDone(todoID: UUID) async throws -> VoiceTodo { storedTodos[0] }
        func deleteCapture(id: UUID) async throws {}
        func deleteTodo(id: UUID) async throws {}
        func fetchCaptures() async throws -> [VoiceCapture] { storedCaptures }
        func fetchTodos() async throws -> [VoiceTodo] { storedTodos }
    }

    @MainActor
    func testWorkspaceViewModelCapturePipelineAndSidebarFiltering() async throws {
        let binding = ProjectBinding(projectKey: "VP", displayName: "VoxPocket", matchKeywords: ["voxpocket"], localDirectoryPath: "/tmp")
        let useCase = FakeCaptureAndTodoUseCase()
        let editing = DefaultEditingUseCase()
        try editing.replaceAll(with: "Fix VoxPocket shortcut")
        let vm = VoxWorkspaceViewModel(
            useCase: useCase,
            projectBindings: [binding],
            editingUseCase: editing
        )
        vm.startCapture(mode: .todo)
        XCTAssertTrue(vm.isRecordingActive)
        await vm.completeCapture()
        XCTAssertFalse(vm.isRecordingActive)
        XCTAssertEqual(vm.captureState, .idle)
        XCTAssertEqual(vm.todos.count, 1)
        XCTAssertEqual(vm.inboxCount, 1)

        vm.searchQuery = "Shortcut"
        vm.selectedSidebarSection = .todoDone
        XCTAssertEqual(vm.selectedTodoFilter, .done)
        XCTAssertTrue(vm.filteredTodos.isEmpty)

        vm.selectedSidebarSection = .project("VP")
        XCTAssertEqual(vm.selectedProjectFilter, "VP")
        XCTAssertEqual(vm.filteredTodos.count, 1)

        vm.clearSearchPreservingFilters()
        XCTAssertEqual(vm.searchQuery, "")
        XCTAssertEqual(vm.selectedProjectFilter, "VP")
    }
}
