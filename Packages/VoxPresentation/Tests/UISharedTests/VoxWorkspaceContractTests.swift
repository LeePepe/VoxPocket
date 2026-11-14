import XCTest
import Combine
import CoreModels
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
        XCTAssertTrue(vm.latestCompletedText.contains("好的工具应当像空气一样安静"))
        let restored = VoxWorkspaceViewModel(useCase: useCase)
        restored.searchQuery = "no-match"
        restored.sortOrder = .oldestFirst
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

    #if os(macOS)
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
