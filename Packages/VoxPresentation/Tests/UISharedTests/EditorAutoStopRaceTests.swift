import Combine
import CoreModels
import LLMKit
import TextHistory
import TranscriptionKit
import UIShared
import UseCases
import XCTest

@MainActor
final class EditorAutoStopRaceTests: XCTestCase {
    func testAutoStopSchedulesWhenRecordingStateBecomesActiveAfterLiveText() async {
        let recording = ManualRecordingUseCase()
        let transcription = ManualTranscriptionUseCase()
        let editor = EditorViewModel(
            recording: recording,
            transcription: transcription,
            editing: NoopEditingUseCase(),
            history: NoopHistoryUseCase(),
            refinement: NoopRefinementUseCase()
        )

        await editor.startRecording()
        transcription.emitLiveText("hello")
        recording.setState(.recording(duration: 0))

        try? await Task.sleep(for: .seconds(3))

        XCTAssertEqual(recording.stopCallCount, 1)
    }
}

private final class ManualRecordingUseCase: RecordingUseCase, @unchecked Sendable {
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
        // Intentionally leave state unchanged to simulate delayed state update.
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

    func checkPermission() async -> Bool { true }

    func requestPermission() async -> Bool { true }

    func setState(_ state: RecordingState) {
        stateSubject.send(state)
    }
}

private final class ManualTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {
    private let liveTextSubject = PassthroughSubject<String, Never>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private var _currentLanguage: Locale = Locale(identifier: "zh-Hans")

    var liveTextPublisher: AnyPublisher<String, Never> {
        liveTextSubject.eraseToAnyPublisher()
    }

    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        finalResultSubject.eraseToAnyPublisher()
    }

    var currentLanguage: Locale { _currentLanguage }
    var supportedLanguages: [Locale] { [_currentLanguage] }

    func setLanguage(_ locale: Locale) { _currentLanguage = locale }

    func commitCurrentTranscription() async throws {}

    func clearLiveText() {
        liveTextSubject.send("")
    }

    func emitLiveText(_ text: String) {
        liveTextSubject.send(text)
    }
}

private final class NoopEditingUseCase: EditingUseCase, @unchecked Sendable {
    private let currentTextSubject = CurrentValueSubject<String, Never>("")
    var currentText: String { currentTextSubject.value }
    var currentTextPublisher: AnyPublisher<String, Never> { currentTextSubject.eraseToAnyPublisher() }
    func applyEdit(range: CoreModels.TextRange, newText: String) throws {}
    func replaceAll(with text: String) throws { currentTextSubject.send(text) }
    func insert(_ text: String, at location: Int) throws {}
    func delete(range: CoreModels.TextRange) throws {}
    func append(_ text: String) throws {}
    func mergeRecentEdits() {}
}

private final class NoopHistoryUseCase: HistoryUseCase, @unchecked Sendable {
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
    func undo() throws {}
    func redo() throws {}
    func getHistoryState() -> TextHistoryState { historyStateSubject.value }
    func createCheckpoint() {}
    func clearHistory() {}
}

private final class NoopRefinementUseCase: RefinementUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RefinementState, Never>(.idle)
    var state: RefinementState { stateSubject.value }
    var statePublisher: AnyPublisher<RefinementState, Never> { stateSubject.eraseToAnyPublisher() }
    var isConfigured: Bool { false }
    func refine(customPrompt: String?) async throws {}
    func refineSelection(range: NSRange, customPrompt: String?) async throws {}
    func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
    func cancel() { stateSubject.send(.idle) }
}
