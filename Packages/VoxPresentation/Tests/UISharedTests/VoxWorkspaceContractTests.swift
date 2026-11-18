import XCTest
import Combine
import CoreModels
import Persistence
import PlatformAdapters
import Preferences
import UseCases
@testable import UIShared
#if os(macOS)
import AppKit
import SwiftUI
import Vision
#endif

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
    func testTodoReminderRescheduleShiftSlotAssignmentAndClearing() async throws {
        let useCase = FakeCaptureAndTodoUseCase()
        let vm = VoxWorkspaceViewModel(useCase: useCase)
        let created = try await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "提醒我早上取快递",
            refinedText: "取快递",
            localAudioFileName: nil,
            durationSeconds: 3,
            deviceSource: .iPhone
        )
        let todo = try XCTUnwrap(created.todo)
        await vm.reload()

        vm.assignTodoHabitSlot(todoID: todo.id, slotRawValue: "morning")
        try await Task.sleep(for: .milliseconds(50))
        let afterAssign = try XCTUnwrap(vm.todos.first(where: { $0.id == todo.id }))
        XCTAssertEqual(afterAssign.timeSlot, "morning")
        let initialScheduled = try XCTUnwrap(afterAssign.scheduledAt)

        vm.shiftTodoReminderByMinutes(todoID: todo.id, deltaMinutes: 15)
        try await Task.sleep(for: .milliseconds(50))
        let afterShift = try XCTUnwrap(vm.todos.first(where: { $0.id == todo.id }))
        let shiftedScheduled = try XCTUnwrap(afterShift.scheduledAt)
        XCTAssertEqual(shiftedScheduled.timeIntervalSince(initialScheduled), 15 * 60, accuracy: 1.0)

        vm.clearTodoReminder(todoID: todo.id)
        try await Task.sleep(for: .milliseconds(50))
        let afterClear = try XCTUnwrap(vm.todos.first(where: { $0.id == todo.id }))
        XCTAssertNil(afterClear.scheduledAt)
        XCTAssertNil(afterClear.timeSlot)
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

    @MainActor
    func testTodoDeletionAndCompletedCleanupContracts() async throws {
        let useCase = FakeCaptureAndTodoUseCase()
        let vm = VoxWorkspaceViewModel(useCase: useCase)
        let created = try await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "删除测试待办",
            refinedText: "删除测试待办",
            localAudioFileName: nil,
            durationSeconds: 1,
            deviceSource: .iPhone
        )
        let todo = try XCTUnwrap(created.todo)
        let subtask = VoiceTodoSubtask(title: "测试子步骤")
        _ = try await useCase.updateTodo(todo.withAppendedSubtask(subtask.title))
        await vm.reload()
        let saved = try XCTUnwrap(vm.todos.first)
        vm.expandedTodoID = saved.id
        vm.selectedTodoID = saved.id
        vm.deleteTodoSubtask(todoID: saved.id, subtaskID: try XCTUnwrap(saved.subtasks.first).id)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(vm.todos.first?.subtasks.count, 0)

        vm.deleteTodo(saved.id)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(vm.todos.isEmpty)
        XCTAssertNil(vm.expandedTodoID)
        XCTAssertNil(vm.selectedTodoID)
        XCTAssertEqual(vm.lastCopiedBannerText, "已删除待办 · 删除测试待办")

        let done = try await useCase.recordCompletedCapture(mode: .todo, rawTranscript: "完成项", refinedText: "完成项", localAudioFileName: nil, durationSeconds: 1, deviceSource: .iPhone)
        _ = try await useCase.markTodoDone(todoID: try XCTUnwrap(done.todo).id)
        await vm.reload()
        vm.clearCompletedTodos()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(vm.doneCount, 0)
        XCTAssertEqual(vm.lastCopiedBannerText, "已清理 1 项已完成待办")
    }

    @MainActor
    func testPreviewStoreDeletionContracts() {
        let store = TodoUnfoldVariantPreviewStore(variant: .v03, initiallyExpanded: true)
        let todo = store.todos[0]
        let subtaskID = todo.subtasks[0].id
        store.deleteSubtask(todoID: todo.id, subtaskID: subtaskID)
        XCTAssertFalse(store.todos[0].subtasks.contains { $0.id == subtaskID })
        store.deleteTodo(todoID: todo.id)
        XCTAssertFalse(store.todos.contains { $0.id == todo.id })
        store.clearCompletedTodos()
        XCTAssertTrue(store.todos.allSatisfy { $0.executionState != .done })
    }

    private actor FakeCaptureAndTodoUseCase: VoiceCaptureAndTodoUseCase {
        var storedCaptures: [VoiceCapture]
        var storedTodos: [VoiceTodo] = []
        init(storedCaptures: [VoiceCapture] = []) { self.storedCaptures = storedCaptures }
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
        func updateTodo(_ todo: VoiceTodo) async throws -> VoiceTodo {
            if let index = storedTodos.firstIndex(where: { $0.id == todo.id }) {
                storedTodos[index] = todo
            } else {
                storedTodos.append(todo)
            }
            return todo
        }
        func runTodoWithAI(todoID: UUID, project: ProjectBinding, template: AIRunnerTemplate) async throws -> VoiceTodo { storedTodos[0] }
        func markTodoDone(todoID: UUID) async throws -> VoiceTodo {
            guard let index = storedTodos.firstIndex(where: { $0.id == todoID }) else { throw NSError(domain: "test", code: 1) }
            let updated = storedTodos[index].withExecutionState(.done, completedAt: Date())
            storedTodos[index] = updated
            return updated
        }
        func deleteCapture(id: UUID) async throws {}
        func deleteTodo(id: UUID) async throws {
            storedTodos.removeAll { $0.id == id }
        }
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
        XCTAssertTrue(vm.latestCompletedText.contains("好的工具应当像空气一样安静"))
        let restored = VoxWorkspaceViewModel(useCase: useCase)
        restored.searchQuery = "no-match"
        restored.sortOrder = .oldestFirst
        await restored.reload()
        await restored.seedDemoDataIfEmptyForPreview()
        XCTAssertEqual(restored.latestCompletedText, vm.latestCompletedText)
        XCTAssertTrue(restored.filteredCaptures.isEmpty)
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

    @MainActor
    func testWorkspacePhysicalReleaseWaitsForActualInjectedStartAndIgnoresDuplicateFinish() async {
        let gate = RecorderTestGate()
        let recording = ControlledRecordingUseCase(gate: gate)
        let editing = DefaultEditingUseCase()
        let vm = VoxWorkspaceViewModel(useCase: FakeCaptureAndTodoUseCase(), preferencesStore: InMemoryTestPreferencesStore(),
                                       recordingUseCase: recording, editingUseCase: editing)
        var time = 0.0
        let controller = RecorderGestureController(now: { time })
        let capture = RecorderGestureController.Capture(isRecording: false, isProcessing: false,
            start: { await vm.startCaptureAndWait() }, stop: { await vm.completeCapture() }, cancel: { vm.cancelCapture() })
        controller.pressBegan(capture)
        await gate.waitForEntries()
        vm.startCapture(mode: .todo)
        try? editing.replaceAll(with: "Paused-start synthetic sentence")
        time = 0.3
        controller.pressEnded()
        XCTAssertEqual(recording.events, ["start-requested"])
        await gate.releaseNext()
        await controller.waitForSettled()
        await vm.completeCapture()
        XCTAssertEqual(recording.events, ["start-requested", "started", "stopped"])
        XCTAssertEqual(vm.captures.count, 1)
        XCTAssertEqual(vm.latestCompletedText, "Paused-start synthetic sentence")
        XCTAssertEqual(vm.captureState, .idle)
    }

    @MainActor func testWorkspaceStage4VoiceAppendAndDemoTodoRecording() async throws {
        let captures = DefaultVoiceCaptureRepository()
        let todos = DefaultVoiceTodoRepository()
        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let realUseCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: DefaultVoiceTodoExtractor(),
            runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir)
        )
        let vm = VoxWorkspaceViewModel(useCase: realUseCase)
        vm.isDemoRecordingEnabled = true
        vm.startCapture(mode: .todo)
        await vm.completeCapture(deviceSource: .iPhone)
        XCTAssertEqual(vm.todos.count, 1)
        let demoTodo = try XCTUnwrap(vm.todos.first)
        XCTAssertLessThanOrEqual(demoTodo.title.count, 14)
        XCTAssertGreaterThanOrEqual(demoTodo.subtasks.count, 2)
        XCTAssertTrue(demoTodo.tags.contains("#VoxPocket"))

        let appended = try await vm.appendVoiceCaptureToTodo(
            demoTodo.id,
            subtaskTitle: "先补充降低透明度对比度检查，再导出双外观对比图 #Design",
            rawTranscript: "先补充降低透明度对比度检查，再导出双外观对比图 #Design",
            deviceSource: .iPhone
        )
        XCTAssertGreaterThanOrEqual(appended.subtasks.count, 4)
        XCTAssertGreaterThanOrEqual(vm.voiceAppendedSubtasks(for: demoTodo.id).count, 2)
    }

    @MainActor
    func testDirectWorkspaceCancelDuringStartCancelsAgainAfterMicrophoneActuallyStarts() async {
        let gate = RecorderTestGate()
        let recording = ControlledRecordingUseCase(gate: gate)
        let vm = VoxWorkspaceViewModel(useCase: FakeCaptureAndTodoUseCase(), recordingUseCase: recording)
        let start = Task { await vm.startCaptureAndWait() }
        await gate.waitForEntries()
        vm.cancelCapture()
        await gate.releaseNext()
        await start.value
        XCTAssertFalse(recording.state.isActive)
        XCTAssertEqual(recording.events.last, "cancelled")
        XCTAssertEqual(vm.captureState, .idle)
        XCTAssertTrue(vm.captures.isEmpty)
    }

    @MainActor
    func testLatestSuccessfulCaptureUsesRawFallbackWithoutClipboardOrFilterSideEffects() async {
        let useCase = FakeCaptureAndTodoUseCase(storedCaptures: [
            VoiceCapture(rawTranscript: "latest raw", state: .completed, createdAt: Date(timeIntervalSince1970: 20)),
            VoiceCapture(rawTranscript: "old raw", refinedText: "old refined", state: .completed, createdAt: Date(timeIntervalSince1970: 10)),
            VoiceCapture(rawTranscript: "failed", state: .failed(stage: .asr, reason: "Synthetic"), createdAt: Date(timeIntervalSince1970: 30))
        ])
        var copies: [String] = []
        let vm = VoxWorkspaceViewModel(useCase: useCase, onCopyTextToClipboard: { copies.append($0) })
        vm.searchQuery = "no-match"
        vm.sortOrder = .oldestFirst
        await vm.reload()
        XCTAssertEqual(vm.latestCompletedText, "latest raw")
        XCTAssertTrue(vm.filteredCaptures.isEmpty)
        XCTAssertTrue(copies.isEmpty)
        vm.copyLatestCompletedText()
        XCTAssertEqual(copies, ["latest raw"])
    }

    @MainActor
    func testInjectedPublishersDriveLiveAndProcessingSentenceBeforeCompletion() async throws {
        let transcription = WorkspaceTranscriptionProbe()
        let editing = DefaultEditingUseCase()
        let gate = RecorderTestGate()
        let vm = VoxWorkspaceViewModel(useCase: FakeCaptureAndTodoUseCase(), captureRecorder: { _ in
            await gate.suspend()
            return (rawTranscript: "synthetic raw", refinedText: "synthetic final", localAudioFileName: nil, durationSeconds: 1)
        }, transcriptionUseCase: transcription, editingUseCase: editing)
        vm.startCapture(mode: .text)
        let live = expectation(description: "Injected live text reaches the stage")
        let liveSubscription = vm.$liveTranscription.filter { $0 == "synthetic live" }.sink { _ in live.fulfill() }
        transcription.send("synthetic live")
        await fulfillment(of: [live], timeout: 2)
        let completion = Task { await vm.completeCapture() }
        await gate.waitForEntries()
        XCTAssertTrue(vm.isProcessingCapture)
        let streaming = expectation(description: "Injected editing stream reaches the processing stage")
        let streamSubscription = vm.$streamingRefinedText.filter { $0 == "synthetic stream" }.sink { _ in streaming.fulfill() }
        try editing.replaceAll(with: "synthetic stream")
        await fulfillment(of: [streaming], timeout: 2)
        await gate.releaseNext()
        await completion.value
        XCTAssertEqual(vm.latestCompletedText, "synthetic final")
        XCTAssertEqual(vm.captureState, .idle)
        withExtendedLifetime((liveSubscription, streamSubscription)) {}
    }

    @MainActor
    func testSyntheticRecordingCannotBeErasedByQueuedRealPublisherClears() async {
        let transcription = WorkspaceTranscriptionProbe()
        let vm = VoxWorkspaceViewModel(useCase: FakeCaptureAndTodoUseCase(), transcriptionUseCase: transcription,
                                       editingUseCase: DefaultEditingUseCase())
        vm.isDemoRecordingEnabled = true
        await vm.startCaptureAndWait()
        transcription.send("")
        let drained = expectation(description: "Queued publisher delivery drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertTrue(vm.liveTranscription.hasPrefix("把刚才散步想到的播客开场白"))
        XCTAssertEqual(vm.audioLevel, 0.72)
        await vm.completeCapture()
        XCTAssertTrue(vm.latestCompletedText.hasPrefix("播客开场灵感："))
        XCTAssertEqual(vm.captureState, .idle)
    }

    @MainActor
    func testSlidePageNavigationExpandableTodoAndSameTodoVoiceAppend() async throws {
        let useCase = FakeCaptureAndTodoUseCase()
        let editing = DefaultEditingUseCase()
        let vm = VoxWorkspaceViewModel(
            useCase: useCase,
            preferencesStore: InMemoryTestPreferencesStore(),
            defaultCaptureMode: .text,
            editingUseCase: editing
        )
        XCTAssertEqual(vm.activePage, .recorder)
        XCTAssertNil(vm.expandedTodoID)

        // Slide to Todo Page: recording with no expanded todo creates a new VoiceTodo
        vm.toggleActivePage()
        XCTAssertEqual(vm.activePage, .todo)
        vm.startCaptureInPreferredMode()
        XCTAssertEqual(vm.captureState, .recording(mode: .todo))
        try editing.replaceAll(with: "整理 iOS 双按钮极简导航验收")
        await vm.completeCapture(deviceSource: .iPhone)
        XCTAssertEqual(vm.todos.count, 1)
        let createdTodo = try XCTUnwrap(vm.todos.first)
        XCTAssertEqual(createdTodo.title, "整理 iOS 双按钮极简导航验收")
        XCTAssertEqual(vm.lastCopiedBannerText, "已存入待办 · 整理 iOS 双按钮极简导航验收")

        // Tap to expand Todo in-place, then press Record: appends voice capture as a subtask to the expanded Todo
        vm.toggleExpandedTodo(createdTodo.id)
        XCTAssertEqual(vm.expandedTodoID, createdTodo.id)
        XCTAssertEqual(vm.appendingTargetTodoTitle, "整理 iOS 双按钮极简导航验收")

        vm.startCaptureInPreferredMode()
        XCTAssertTrue(vm.isRecordingActive)
        XCTAssertEqual(vm.appendingTargetTodoID, createdTodo.id)
        try editing.replaceAll(with: "补齐展开态语音直补子任务单测")
        await vm.completeCapture(refinedText: "补齐展开态语音直补子任务单测", deviceSource: .iPhone)

        // Must NOT create a second standalone VoiceTodo; must append to the expanded Todo
        XCTAssertEqual(vm.todos.count, 1)
        let updatedTodo = try XCTUnwrap(vm.todos.first)
        XCTAssertEqual(updatedTodo.subtasks.count, 1)
        XCTAssertEqual(updatedTodo.subtasks[0].title, "补齐展开态语音直补子任务单测")
        XCTAssertFalse(updatedTodo.subtasks[0].isCompleted)
        XCTAssertEqual(vm.lastCopiedBannerText, "已补充至待办 · 整理 iOS 双按钮极简导航验收")

        // Toggle subtask completion and priority
        vm.toggleTodoSubtask(todoID: updatedTodo.id, subtaskID: updatedTodo.subtasks[0].id)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.subtasks.first?.isCompleted, true)
        XCTAssertEqual(vm.voiceAppendedSubtasks(for: updatedTodo.id).count, 1)

        // Direct in-place manipulation: subtask title, todo title, status cycle, priority cycle, historical tags & add tag
        let firstSubtaskID = try XCTUnwrap(vm.todos.first?.subtasks.first?.id)
        vm.updateTodoSubtaskTitle(todoID: updatedTodo.id, subtaskID: firstSubtaskID, title: "原地修改后的子任务标题")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.subtasks.first?.title, "原地修改后的子任务标题")

        vm.updateTodoTitle(todoID: updatedTodo.id, title: "原地修改后的顶部聚焦标题")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.title, "原地修改后的顶部聚焦标题")
        vm.updateTodoTitle(todoID: updatedTodo.id, title: "   ")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.title, "原地修改后的顶部聚焦标题")

        vm.updateTodoDescription(todoID: updatedTodo.id, description: "  展开态可编辑的详细背景说明  ")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.description, "展开态可编辑的详细背景说明")

        vm.cycleTodoStatus(todoID: updatedTodo.id)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.executionState, .running)
        vm.cycleTodoStatus(todoID: updatedTodo.id)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.executionState, .done)
        vm.cycleTodoStatus(todoID: updatedTodo.id)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.executionState, .inbox)

        vm.updateTodoPriority(todoID: updatedTodo.id, priority: .p0)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.priority, .p0)
        vm.cycleTodoPriority(todoID: updatedTodo.id)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.priority, .p1)

        XCTAssertTrue(vm.availableHistoricalTags.contains("#VoxPocket"))
        XCTAssertTrue(vm.availableHistoricalTags.contains("#AI"))
        vm.toggleTodoTag(todoID: updatedTodo.id, tag: "#VoxPocket")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.tags, ["#VoxPocket"])
        vm.addTodoTag(todoID: updatedTodo.id, tag: "Design")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.tags, ["#VoxPocket", "#Design"])
        XCTAssertTrue(vm.availableHistoricalTags.contains("#Design"))

        // Verify multi-dimensional (status x priority x tag) filtering and resetAllTodoFilters in VoxWorkspaceViewModel
        XCTAssertFalse(vm.hasActiveTodoFilters)
        vm.togglePriorityFilter(.p0)
        XCTAssertEqual(vm.selectedPriorityFilter, .p0)
        XCTAssertTrue(vm.hasActiveTodoFilters)
        XCTAssertTrue(vm.filteredTodos.isEmpty) // current todo is .p1
        vm.togglePriorityFilter(.p1)
        XCTAssertEqual(vm.selectedPriorityFilter, .p1)
        XCTAssertEqual(vm.filteredTodos.count, 1)
        vm.toggleTagFilter("#Design")
        XCTAssertEqual(vm.selectedTagFilter, "#Design")
        XCTAssertEqual(vm.filteredTodos.count, 1)
        vm.toggleTagFilter("#Podcast")
        XCTAssertEqual(vm.selectedTagFilter, "#Podcast")
        XCTAssertTrue(vm.filteredTodos.isEmpty)
        vm.resetAllTodoFilters()
        XCTAssertFalse(vm.hasActiveTodoFilters)
        XCTAssertEqual(vm.selectedTodoFilter, .all)
        XCTAssertNil(vm.selectedPriorityFilter)
        XCTAssertNil(vm.selectedTagFilter)
        XCTAssertEqual(vm.filteredTodos.count, 1)

        vm.toggleTodoTag(todoID: updatedTodo.id, tag: "#VoxPocket")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(vm.todos.first?.tags, ["#Design"])

        // Companion tray excludes the currently expanded todo
        XCTAssertTrue(vm.companionTodos.isEmpty)

        // Collapse Todo and slide back to Recorder Page
        vm.toggleExpandedTodo(updatedTodo.id)
        XCTAssertNil(vm.expandedTodoID)
        XCTAssertEqual(vm.companionTodos.count, 1)
        vm.toggleActivePage()
        XCTAssertEqual(vm.activePage, .recorder)

        // Start recording on Recorder Page, then switch to Todo Page and expand a Todo before completion:
        // must respect the start-time destination (.text) and NOT append to the newly expanded Todo.
        XCTAssertEqual(vm.selectedCaptureMode, .text)
        vm.startCaptureInPreferredMode()
        XCTAssertEqual(vm.captureState, .recording(mode: .text))
        XCTAssertNil(vm.appendingTargetTodoID)
        vm.toggleActivePage()
        vm.toggleExpandedTodo(updatedTodo.id)
        try editing.replaceAll(with: "独立速记不应混入展开待办")
        await vm.completeCapture(refinedText: "独立速记不应混入展开待办", deviceSource: .iPhone)
        XCTAssertEqual(vm.todos.first?.subtasks.count, 1)
        XCTAssertEqual(vm.lastCopiedBannerText, "已复制到剪贴板 · 可直接粘贴")
    }

    @MainActor
    func testEmptySpeechCaptureClearsPreviousLatestCompletedText() async throws {
        let useCase = FakeCaptureAndTodoUseCase()
        let editing = DefaultEditingUseCase()
        let vm = VoxWorkspaceViewModel(
            useCase: useCase,
            preferencesStore: InMemoryTestPreferencesStore(),
            defaultCaptureMode: .text,
            editingUseCase: editing
        )

        // First capture completes with recognized text
        vm.startCapture(mode: .text)
        try editing.replaceAll(with: "第一段识别内容")
        await vm.completeCapture(deviceSource: .iPhone)
        XCTAssertEqual(vm.latestCompletedText, "第一段识别内容")
        XCTAssertEqual(vm.captureState, .idle)

        // Starting a new capture immediately clears the previous recognized text and editing buffer
        vm.startCapture(mode: .text)
        XCTAssertEqual(vm.latestCompletedText, "")
        XCTAssertEqual(vm.liveTranscription, "")
        XCTAssertEqual(editing.currentText, "")

        // Completing the second capture with empty speech must NOT retain "第一段识别内容"
        await vm.completeCapture(rawTranscript: "", refinedText: "", deviceSource: .iPhone)
        XCTAssertEqual(vm.latestCompletedText, "")
        XCTAssertEqual(vm.captureState, .idle)
        XCTAssertEqual(vm.lastCopiedBannerText, "未检测到语音，按住底部麦克风重新说话。")
    }

    #if os(macOS)
    @MainActor
    func testIOSCleanSlateWorkspaceViewAndFourUpSwiftUIPreviewsRenderOnMacOS() async throws {
        let previewVM = IOSCleanSlatePreviewFactory.makePreviewViewModel(
            activePage: .todo,
            expandFirstTodo: true
        )
        let iosHost = NSHostingView(
            rootView: IOSCleanSlateWorkspaceView(viewModel: previewVM)
                .environment(\.colorScheme, .dark)
                .frame(width: 390, height: 844)
        )
        iosHost.frame = NSRect(x: 0, y: 0, width: 390, height: 844)
        iosHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(iosHost.bounds.width, 390)
        XCTAssertEqual(iosHost.bounds.height, 844)

        let boardController = TodoUnfoldFourUpBoardController(initiallyExpanded: true)
        XCTAssertEqual(TodoUnfoldVariantKind.allCases.count, 4)
        for kind in TodoUnfoldVariantKind.allCases {
            let store = boardController.store(for: kind)
            XCTAssertNotNil(store.expandedTodoID)
            XCTAssertGreaterThanOrEqual(store.todos.count, 6)
            XCTAssertEqual(store.filteredTodos.count, store.todos.count)
            // Verify real multi-dimensional filtering in TodoUnfoldVariantPreviewStore across all 4 distinct architectures
            store.selectFilterOption("待处理")
            XCTAssertEqual(store.filteredTodos.count, 3)
            XCTAssertTrue(store.filteredTodos.allSatisfy { $0.executionState == .inbox })
            store.selectPriorityFilter(.p0)
            XCTAssertEqual(store.filteredTodos.count, 2)
            XCTAssertTrue(store.filteredTodos.allSatisfy { $0.executionState == .inbox && $0.priority == .p0 })
            store.selectTagFilter("#iOS")
            XCTAssertEqual(store.filteredTodos.count, 1)
            XCTAssertEqual(store.filteredTodos.first?.title, "液态玻璃交互走查")
            store.selectFilterOption("已完成")
            XCTAssertTrue(store.filteredTodos.isEmpty) // no done todo has P0 + #iOS
            store.resetFilters()
            XCTAssertFalse(store.hasActiveFilters)
            XCTAssertEqual(store.filteredTodos.count, store.todos.count)
            // Verify conditional subtask progress rule: items with >= 2 subtasks vs <= 1 subtask both exist in preview dataset
            XCTAssertTrue(store.todos.contains(where: { $0.subtasks.count >= 2 }))
            XCTAssertTrue(store.todos.contains(where: { $0.subtasks.count <= 1 }))
            for item in store.todos {
                XCTAssertLessThanOrEqual(item.title.count, 14)
                XCTAssertFalse(item.description.isEmpty)
            }
            let viewportHost = NSHostingView(
                rootView: TodoUnfoldVariantPhoneViewport(store: store, interpolationProgress: 1.0)
                    .frame(width: 390, height: 844)
            )
            viewportHost.frame = NSRect(x: 0, y: 0, width: 390, height: 844)
            viewportHost.layoutSubtreeIfNeeded()
            XCTAssertEqual(viewportHost.bounds.size, NSSize(width: 390, height: 844))

            let collapsedHost = NSHostingView(
                rootView: TodoUnfoldVariantPhoneViewport(store: store, interpolationProgress: 0.0)
                    .frame(width: 390, height: 844)
            )
            collapsedHost.frame = NSRect(x: 0, y: 0, width: 390, height: 844)
            collapsedHost.layoutSubtreeIfNeeded()
            XCTAssertEqual(collapsedHost.bounds.size, NSSize(width: 390, height: 844))
        }
        boardController.toggleAllTagTrays()
        XCTAssertTrue(boardController.allTagTraysOpen)
        boardController.toggleAllExpanded()
        XCTAssertFalse(boardController.allExpanded)

        // Also verify Recorder Page hides bottom-left Filter while Todo Page shows it
        let recorderPreviewVM = IOSCleanSlatePreviewFactory.makePreviewViewModel(
            activePage: .recorder,
            expandFirstTodo: false
        )
        XCTAssertEqual(recorderPreviewVM.activePage, .recorder)
        let recorderHost = NSHostingView(
            rootView: IOSCleanSlateWorkspaceView(viewModel: recorderPreviewVM)
                .environment(\.colorScheme, .dark)
                .frame(width: 390, height: 844)
        )
        recorderHost.frame = NSRect(x: 0, y: 0, width: 390, height: 844)
        recorderHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(recorderHost.bounds.size, NSSize(width: 390, height: 844))
        XCTAssertEqual(boardController.store(for: .v02).variant.badgeCode, "V02")

        // Verify RecorderBackdrop active stage atmosphere opacity contract (T6)
        XCTAssertEqual(RecorderBackdrop.atmosphereOpacity(for: .idle, colorScheme: .dark), 0.10, accuracy: 0.001)
        XCTAssertEqual(RecorderBackdrop.atmosphereOpacity(for: .idle, colorScheme: .light), 0.28, accuracy: 0.001)
        for activeStage: RecorderStatus in [.listening, .transcribing, .refining, .done, .error] {
            XCTAssertEqual(RecorderBackdrop.atmosphereOpacity(for: activeStage, colorScheme: .dark), 0.62, accuracy: 0.001)
            XCTAssertEqual(RecorderBackdrop.atmosphereOpacity(for: activeStage, colorScheme: .light), 0.46, accuracy: 0.001)
        }
        // Todo list preview store background stays constantly at .idle while Recorder Page (Tab 2) switches 5 stages
        XCTAssertEqual(boardController.store(for: .v02).recorderStatus, .idle)
        boardController.setAllRecorderStages(.listening)
        XCTAssertEqual(boardController.recorderStagesByBezel[0], .listening)
        XCTAssertEqual(boardController.store(for: .v02).recorderStatus, .idle)
        boardController.setAllRecorderStages(.refining)
        XCTAssertEqual(boardController.recorderStagesByBezel[0], .refining)
        boardController.setAllRecorderStages(.idle)
        XCTAssertEqual(PreviewHostTopTab.allCases.count, 4)
        XCTAssertTrue(PreviewHostTopTab.allCases.contains(.macOSDesktopWorkspace))
        XCTAssertEqual(PreviewHostTopTab.macOSDesktopWorkspace.label, "Tab 4 · macOS 桌面工作台预览")
        XCTAssertEqual(boardController.activeTab, .dynamicIslandFourVariants)
        XCTAssertEqual(DynamicIslandPreviewVariantKind.allCases.count, 4)
        XCTAssertEqual(DynamicIslandDataPreset.allCases.count, 4)

        // Verify Tab 4 macOS Desktop Workspace Preview & 4 destinations render cleanly
        boardController.activeTab = .macOSDesktopWorkspace
        XCTAssertEqual(MacOSWorkspaceDestination.allCases.count, 4)
        for dest in MacOSWorkspaceDestination.allCases {
            boardController.macWorkspaceDestination = dest
            let macHost = NSHostingView(
                rootView: MacOSCleanSlateWorkspaceView(
                    viewModel: boardController.macPreviewViewModel,
                    initialDestination: dest
                )
                .environment(\.colorScheme, .dark)
                .frame(width: 1280, height: 760)
            )
            macHost.frame = NSRect(x: 0, y: 0, width: 1280, height: 760)
            macHost.layoutSubtreeIfNeeded()
            XCTAssertEqual(macHost.bounds.size, NSSize(width: 1280, height: 760))
        }
        boardController.activeTab = .dynamicIslandFourVariants

        // Verify Dynamic Island conditional description + horizontal subtasks + voice/AI actions across all 4 presets
        boardController.islandDataPreset = .fullWithSubtasksAndDescription
        XCTAssertFalse(boardController.islandDescriptionByVariant[.diV01]?.isEmpty ?? true)
        XCTAssertEqual(boardController.islandSubtasksByVariant[.diV01]?.count, 4)
        let fullHeight = DynamicIslandPreviewVariantKind.diV04.expandedHeight(hasDescription: true, hasSubtasks: true)

        boardController.islandDataPreset = .minimalTitleOnly
        XCTAssertTrue(boardController.islandDescriptionByVariant[.diV01]?.isEmpty ?? false)
        XCTAssertTrue(boardController.islandSubtasksByVariant[.diV01]?.isEmpty ?? false)
        let shrunkHeight = DynamicIslandPreviewVariantKind.diV04.expandedHeight(hasDescription: false, hasSubtasks: false)
        XCTAssertLessThan(shrunkHeight, fullHeight)

        boardController.appendVoiceSubtaskOnIsland(for: .diV01)
        XCTAssertEqual(boardController.islandSubtasksByVariant[.diV01]?.count, 1)
    }

    @MainActor
    func testNativeMacWorkspaceRendersSharedHomeAtActualMinimumSize() async throws {
        let vm = VoxWorkspaceViewModel(useCase: FakeCaptureAndTodoUseCase())
        await vm.seedDemoDataIfEmptyForPreview()
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: MacOSCleanSlateWorkspaceView(viewModel: vm)
                .environment(\.colorScheme, scheme)
                .frame(width: 820, height: 520))
            let panel = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 820, height: 520),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            panel.contentView = host
            panel.orderFront(nil)
            defer { panel.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage)
            let background = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 50)?.usingColorSpace(.sRGB))
            let brightness = (background.redComponent + background.greenComponent + background.blueComponent) / 3
            if scheme == .light { XCTAssertGreaterThan(brightness, 0.8) }
            else { XCTAssertLessThan(brightness, 0.6) }
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
            XCTAssertTrue(words.contains("工具应当像空气一样安静"), words)
            XCTAssertFalse(words.contains("选择一个待办"))
            if let directory = ProcessInfo.processInfo.environment["VOX_RECORDER_RENDER_DIR"] {
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("mac-home-\(scheme).png"))
            }
        }
    }
    #endif

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
