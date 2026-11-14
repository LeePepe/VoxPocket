import XCTest
import CoreModels
import Preferences
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
        func markTodoDone(todoID: UUID) async throws -> VoiceTodo {
            guard let index = storedTodos.firstIndex(where: { $0.id == todoID }) else { throw NSError(domain: "test", code: 1) }
            let updated = storedTodos[index].withExecutionState(.done, completedAt: Date())
            storedTodos[index] = updated
            return updated
        }
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
        let vm = VoxWorkspaceViewModel(
            useCase: useCase,
            projectBindings: [binding],
            editingUseCase: editing
        )
        vm.startCapture(mode: .todo)
        XCTAssertTrue(vm.isRecordingActive)
        try editing.replaceAll(with: "Fix VoxPocket shortcut")
        await vm.completeCapture()
        XCTAssertFalse(vm.isRecordingActive)
        XCTAssertEqual(vm.captureState, .idle)
        XCTAssertEqual(vm.todos.count, 1)
        XCTAssertEqual(vm.inboxCount, 1)
        XCTAssertEqual(vm.latestCompletedText, "Fix VoxPocket shortcut")

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

    @MainActor
    func testPreviewSeedIsNaturalAndIdempotent() async throws {
        let useCase = FakeCaptureAndTodoUseCase()
        let vm = VoxWorkspaceViewModel(useCase: useCase)
        await vm.seedDemoDataIfEmptyForPreview()
        await vm.seedDemoDataIfEmptyForPreview()
        XCTAssertEqual(vm.todos.count, 2)
        XCTAssertEqual(vm.captures.count, 3)
        XCTAssertEqual(vm.todos.filter { $0.executionState == .done }.count, 1)
        XCTAssertTrue(vm.captures.contains { $0.refinedText.contains("好的工具应当像空气一样安静") })
    }

    @MainActor
    func testIOSCaptureDestinationPreferenceAndDeterministicReceipt() async throws {
        let store = InMemoryTestPreferencesStore()
        let useCase = FakeCaptureAndTodoUseCase()
        let editing = DefaultEditingUseCase()
        var copiedStrings: [String] = []

        let vm = VoxWorkspaceViewModel(
            useCase: useCase,
            preferencesStore: store,
            defaultCaptureMode: .todo,
            onCopyTextToClipboard: { copiedStrings.append($0) },
            editingUseCase: editing
        )
        XCTAssertEqual(vm.selectedCaptureMode, .todo)

        vm.startCaptureInPreferredMode()
        XCTAssertEqual(vm.captureState, .recording(mode: .todo))
        try editing.replaceAll(with: "Buy coffee beans")
        await vm.completeCapture(deviceSource: .iPhone)
        XCTAssertEqual(vm.lastCopiedBannerText, "已存入待办 · Buy coffee beans")
        XCTAssertEqual(vm.todos.count, 1)
        XCTAssertTrue(copiedStrings.isEmpty)

        vm.updatePreferredCaptureMode(.text)
        try? await Task.sleep(for: .milliseconds(30))
        let persistedMode: CaptureMode? = await store.getValue(for: .iosQuickCaptureDestination)
        XCTAssertEqual(persistedMode, .text)

        vm.startCaptureInPreferredMode()
        XCTAssertEqual(vm.captureState, .recording(mode: .text))
        try editing.replaceAll(with: "Send weekly update")
        await vm.completeCapture(refinedText: "Send weekly update.", deviceSource: .iPhone)
        XCTAssertEqual(vm.lastCopiedBannerText, "已复制到剪贴板 · 可直接粘贴")
        XCTAssertEqual(copiedStrings, ["Send weekly update."])
    }

    private actor InMemoryTestPreferencesStore: PreferencesStore {
        private var storage: [PreferencesKey: Data] = [:]
        func getValue<T: Codable & Sendable>(for key: PreferencesKey) async -> T? {
            guard let data = storage[key] else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        func getValue<T: Codable & Sendable>(for key: PreferencesKey, default defaultValue: T) async -> T {
            if let existing: T = await getValue(for: key) { return existing }
            await setValue(defaultValue, for: key)
            return defaultValue
        }
        func setValue<T: Codable & Sendable>(_ value: T, for key: PreferencesKey) async {
            storage[key] = try? JSONEncoder().encode(value)
        }
        func removeValue(for key: PreferencesKey) async {
            storage.removeValue(forKey: key)
        }
    }
}
