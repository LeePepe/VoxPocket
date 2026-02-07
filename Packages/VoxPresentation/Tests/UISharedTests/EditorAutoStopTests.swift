import Combine
import CoreModels
import LLMKit
import TranscriptionKit
import TextHistory
import UIShared
import UseCases
import XCTest

final class EditorAutoStopTests: XCTestCase {
    @MainActor
    func testStartRecordingClearsLiveTextEachTime() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let editor = EditorViewModel(
            recording: recording,
            transcription: transcription,
            editing: FakeEditingUseCase(),
            history: FakeHistoryUseCase(),
            refinement: FakeRefinementUseCase()
        )

        await editor.startRecording()
        await editor.stopRecording()
        await editor.startRecording()

        XCTAssertEqual(transcription.clearLiveTextCallCount, 2)
    }
}

private final class FakeRecordingUseCase: RecordingUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)

    private(set) var stopCallCount = 0

    var state: RecordingState { stateSubject.value }

    var statePublisher: AnyPublisher<RecordingState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    func startRecording() async throws {
        stateSubject.send(.recording(duration: 0))
    }

    func stopRecording() async throws {
        stopCallCount += 1
        stateSubject.send(.idle)
    }

    func pauseRecording() {
        stateSubject.send(.paused(duration: 0))
    }

    func resumeRecording() {
        stateSubject.send(.recording(duration: 0))
    }

    func cancelRecording() {
        stateSubject.send(.idle)
    }

    func checkPermission() async -> Bool {
        true
    }

    func requestPermission() async -> Bool {
        true
    }
}

private final class FakeTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {
    private let liveTextSubject = PassthroughSubject<String, Never>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()

    private(set) var clearLiveTextCallCount = 0
    private var _currentLanguage: Locale = Locale(identifier: "zh-Hans")

    var liveTextPublisher: AnyPublisher<String, Never> {
        liveTextSubject.eraseToAnyPublisher()
    }

    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        finalResultSubject.eraseToAnyPublisher()
    }

    var currentLanguage: Locale { _currentLanguage }

    var supportedLanguages: [Locale] { [_currentLanguage] }

    func setLanguage(_ locale: Locale) {
        _currentLanguage = locale
    }

    func commitCurrentTranscription() async throws {
    }

    func clearLiveText() {
        clearLiveTextCallCount += 1
        liveTextSubject.send("")
    }
}

private final class FakeEditingUseCase: EditingUseCase, @unchecked Sendable {
    private let currentTextSubject = CurrentValueSubject<String, Never>("")

    var currentText: String { currentTextSubject.value }

    var currentTextPublisher: AnyPublisher<String, Never> {
        currentTextSubject.eraseToAnyPublisher()
    }

    func applyEdit(range: CoreModels.TextRange, newText: String) throws {
    }

    func replaceAll(with text: String) throws {
        currentTextSubject.send(text)
    }

    func insert(_ text: String, at location: Int) throws {
    }

    func delete(range: CoreModels.TextRange) throws {
    }

    func append(_ text: String) throws {
    }

    func mergeRecentEdits() {
    }
}

private final class FakeHistoryUseCase: HistoryUseCase, @unchecked Sendable {
    private let canUndoSubject = CurrentValueSubject<Bool, Never>(false)
    private let canRedoSubject = CurrentValueSubject<Bool, Never>(false)
    private let historyStateSubject = CurrentValueSubject<TextHistoryState, Never>(
        TextHistoryState(currentText: "", canUndo: false, canRedo: false, undoCount: 0, redoCount: 0)
    )

    var canUndo: Bool { canUndoSubject.value }
    var canRedo: Bool { canRedoSubject.value }
    var canUndoPublisher: AnyPublisher<Bool, Never> { canUndoSubject.eraseToAnyPublisher() }
    var canRedoPublisher: AnyPublisher<Bool, Never> { canRedoSubject.eraseToAnyPublisher() }
    var undoCount: Int { 0 }
    var redoCount: Int { 0 }
    var historyStatePublisher: AnyPublisher<TextHistoryState, Never> { historyStateSubject.eraseToAnyPublisher() }

    func undo() throws {
    }

    func redo() throws {
    }

    func getHistoryState() -> TextHistoryState {
        historyStateSubject.value
    }

    func createCheckpoint() {
    }

    func clearHistory() {
    }
}

private final class FakeRefinementUseCase: RefinementUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RefinementState, Never>(.idle)

    var state: RefinementState { stateSubject.value }
    var statePublisher: AnyPublisher<RefinementState, Never> { stateSubject.eraseToAnyPublisher() }
    var isConfigured: Bool { false }

    func refine(customPrompt: String?) async throws {
    }

    func refineSelection(range: NSRange, customPrompt: String?) async throws {
    }

    func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancel() {
        stateSubject.send(.idle)
    }
}
