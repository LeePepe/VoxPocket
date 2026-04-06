import Combine
import CoreModels
import LLMKit
import TranscriptionKit
import TextHistory
import UIShared
import UseCases
import XCTest

/// 验证静默录音（无语音）时 EditorViewModel 的行为：
/// - 不触发 LLM 优化
/// - 显示 "未检测到语音内容" warning snackbar
@MainActor
final class EditorViewModelSilentRecordingTests: XCTestCase {

    // MARK: - New session mode

    func testSilentRecordingNewSessionShowsWarningAndSkipsRefinement() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let editing = FakeEditingUseCase()          // currentText = "" (new session)
        let refinement = FakeConfiguredRefinementUseCase()
        let snackbar = FakeSnackbarService()

        let editor = EditorViewModel(
            recording: recording,
            transcription: transcription,
            editing: editing,
            history: FakeHistoryUseCase(),
            refinement: refinement
        )
        editor.snackbarService = snackbar

        await editor.startRecording()
        // liveTranscription 为空（无语音），commitCurrentTranscription 产生空文本
        await editor.stopRecording()

        XCTAssertEqual(snackbar.warningMessages, ["未检测到语音内容"],
                       "静默录音应弹出 warning snackbar")
        XCTAssertEqual(refinement.refineStreamingCallCount, 0,
                       "静默录音不应触发 LLM 优化")
    }

    // MARK: - Append mode

    func testSilentRecordingAppendModeShowsWarningAndSkipsRefinement() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let editing = FakeEditingUseCase(initialText: "已有内容")  // 续写模式：有旧文本
        let refinement = FakeConfiguredRefinementUseCase()
        let snackbar = FakeSnackbarService()

        let editor = EditorViewModel(
            recording: recording,
            transcription: transcription,
            editing: editing,
            history: FakeHistoryUseCase(),
            refinement: refinement
        )
        editor.snackbarService = snackbar

        // 等待 currentTextPublisher 将旧文本同步到 editor.text
        await Task.yield()

        await editor.startRecording()
        // liveTranscription 为空（无语音）
        await editor.stopRecording()

        XCTAssertEqual(snackbar.warningMessages, ["未检测到语音内容"],
                       "续写模式下静默录音应弹出 warning snackbar")
        XCTAssertEqual(refinement.refineStreamingCallCount, 0,
                       "续写模式下静默录音不应触发 LLM 优化")
        XCTAssertEqual(editing.appendCallCount, 0,
                       "续写模式下静默录音不应向编辑器追加内容")
    }

    // MARK: - Positive case: normal recording with speech should NOT show warning

    /// 使用续写模式（有旧文本）验证：有语音内容时不弹出 warning
    /// 续写模式下 newTranscriptionAdded = !liveTranscription.isEmpty，
    /// 不依赖 FakeTranscriptionUseCase.commitCurrentTranscription() 的实现
    func testRecordingWithSpeechAppendModeDoesNotShowWarning() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let editing = FakeEditingUseCase(initialText: "已有内容")  // 触发续写模式
        let refinement = FakeConfiguredRefinementUseCase()
        let snackbar = FakeSnackbarService()

        let editor = EditorViewModel(
            recording: recording,
            transcription: transcription,
            editing: editing,
            history: FakeHistoryUseCase(),
            refinement: refinement
        )
        editor.snackbarService = snackbar

        await Task.yield()  // 等待 currentTextPublisher 同步到 editor.text

        await editor.startRecording()
        // 模拟有语音输入
        transcription.sendLiveText("你好世界")
        await editor.stopRecording()

        XCTAssertTrue(snackbar.warningMessages.isEmpty,
                      "有语音内容时不应弹出 warning snackbar")
    }
}

// MARK: - Fakes

private final class FakeRecordingUseCase: RecordingUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)

    var state: RecordingState { stateSubject.value }
    var statePublisher: AnyPublisher<RecordingState, Never> { stateSubject.eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { audioLevelSubject.eraseToAnyPublisher() }

    func startRecording() async throws { stateSubject.send(.recording(duration: 0)) }
    func stopRecording() async throws { stateSubject.send(.idle) }
    func pauseRecording() { stateSubject.send(.paused(duration: 0)) }
    func resumeRecording() { stateSubject.send(.recording(duration: 0)) }
    func cancelRecording() { stateSubject.send(.idle) }
    func checkPermission() async -> Bool { true }
    func requestPermission() async -> Bool { true }
}

private final class FakeTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {
    private let liveTextSubject = PassthroughSubject<String, Never>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private var _currentLanguage: Locale = Locale(identifier: "zh-Hans")

    var liveTextPublisher: AnyPublisher<String, Never> { liveTextSubject.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { finalResultSubject.eraseToAnyPublisher() }
    var currentLanguage: Locale { _currentLanguage }
    var supportedLanguages: [Locale] { [_currentLanguage] }

    func sendLiveText(_ text: String) { liveTextSubject.send(text) }
    func setLanguage(_ locale: Locale) { _currentLanguage = locale }
    func commitCurrentTranscription() async throws {}
    func clearLiveText() { liveTextSubject.send("") }
}

private final class FakeEditingUseCase: EditingUseCase, @unchecked Sendable {
    private let currentTextSubject: CurrentValueSubject<String, Never>
    private(set) var appendCallCount = 0

    init(initialText: String = "") {
        currentTextSubject = CurrentValueSubject(initialText)
    }

    var currentText: String { currentTextSubject.value }
    var currentTextPublisher: AnyPublisher<String, Never> { currentTextSubject.eraseToAnyPublisher() }

    func applyEdit(range: CoreModels.TextRange, newText: String) throws {}
    func replaceAll(with text: String) throws { currentTextSubject.send(text) }
    func insert(_ text: String, at location: Int) throws {}
    func delete(range: CoreModels.TextRange) throws {}
    func append(_ text: String) throws { appendCallCount += 1 }
    func mergeRecentEdits() {}
}

private final class FakeHistoryUseCase: HistoryUseCase, @unchecked Sendable {
    private let historyStateSubject = CurrentValueSubject<TextHistoryState, Never>(
        TextHistoryState(currentText: "", canUndo: false, canRedo: false, undoCount: 0, redoCount: 0)
    )
    var canUndo: Bool { false }
    var canRedo: Bool { false }
    var undoCount: Int { 0 }
    var redoCount: Int { 0 }
    var canUndoPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var canRedoPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var historyStatePublisher: AnyPublisher<TextHistoryState, Never> { historyStateSubject.eraseToAnyPublisher() }
    func undo() throws {}
    func redo() throws {}
    func getHistoryState() -> TextHistoryState { historyStateSubject.value }
    func createCheckpoint() {}
    func clearHistory() {}
}

/// isConfigured = true，记录 refineStreaming 调用次数，用于断言优化是否被触发
private final class FakeConfiguredRefinementUseCase: RefinementUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RefinementState, Never>(.idle)
    private(set) var refineStreamingCallCount = 0

    var state: RefinementState { stateSubject.value }
    var statePublisher: AnyPublisher<RefinementState, Never> { stateSubject.eraseToAnyPublisher() }
    var isConfigured: Bool { true }

    func refine(customPrompt: String?) async throws {}
    func refineSelection(range: NSRange, customPrompt: String?) async throws {}

    func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        refineStreamingCallCount += 1
        return AsyncThrowingStream { $0.finish() }
    }

    func cancel() { stateSubject.send(.idle) }
}

@MainActor
private final class FakeSnackbarService: SnackbarService {
    private let currentMessageSubject = CurrentValueSubject<SnackbarMessage?, Never>(nil)
    private(set) var warningMessages: [String] = []

    var currentMessage: SnackbarMessage? { currentMessageSubject.value }
    var currentMessagePublisher: AnyPublisher<SnackbarMessage?, Never> {
        currentMessageSubject.eraseToAnyPublisher()
    }

    func show(_ message: SnackbarMessage) {
        currentMessageSubject.send(message)
        if message.type == .warning {
            warningMessages.append(message.message)
        }
    }

    func dismiss(messageId: UUID?) { currentMessageSubject.send(nil) }
    func clearQueue() {}
}
