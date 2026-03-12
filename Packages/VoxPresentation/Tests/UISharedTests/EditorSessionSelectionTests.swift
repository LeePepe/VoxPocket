import Combine
import CoreModels
import LLMKit
import TextHistory
import TranscriptionKit
import UIShared
import UseCases
import XCTest

final class EditorSessionSelectionTests: XCTestCase {
    @MainActor
    func testCurrentSessionChangeUpdatesEditorText() async {
        let sessionUseCase = FakeSessionUseCase()
        let editor = EditorViewModel(
            recording: NoopRecordingUseCase(),
            transcription: NoopTranscriptionUseCase(),
            editing: FakeEditingUseCase(),
            history: NoopHistoryUseCase(),
            refinement: NoopRefinementUseCase(),
            session: sessionUseCase
        )

        let session = Session(
            id: UUID(),
            title: "历史记录",
            rawText: "原始文本",
            refinedText: "优化文本",
            createdAt: Date(),
            updatedAt: Date(),
            state: .idle
        )

        sessionUseCase.pushCurrentSession(session)
        for _ in 0..<20 where editor.text != session.displayText {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(editor.text, session.displayText)
    }
}

private final class FakeSessionUseCase: SessionUseCase, @unchecked Sendable {
    private let currentSessionSubject = CurrentValueSubject<Session?, Never>(nil)
    private let sessionsSubject = CurrentValueSubject<[Session], Error>([])

    var currentSession: Session? { currentSessionSubject.value }
    var currentSessionPublisher: AnyPublisher<Session?, Never> { currentSessionSubject.eraseToAnyPublisher() }
    var sessionsPublisher: AnyPublisher<[Session], Error> { sessionsSubject.eraseToAnyPublisher() }

    func pushCurrentSession(_ session: Session?) {
        currentSessionSubject.send(session)
    }

    func createSession(title: String?) async throws -> Session {
        let session = Session(title: title ?? "Session")
        currentSessionSubject.send(session)
        return session
    }

    func loadSession(_ id: UUID) async throws {}

    func saveCurrentSession() async throws {}

    func fetchAllSessions() async throws -> [Session] {
        []
    }

    func deleteSession(_ id: UUID) async throws {}

    func updateSessionTitle(_ id: UUID, title: String) async throws {}

    func closeCurrentSession() async throws {
        currentSessionSubject.send(nil)
    }

    func saveCompletedSession(title: String?, rawText: String, refinedText: String) async throws -> Session {
        Session(title: title ?? "Session", rawText: rawText, refinedText: refinedText)
    }
}

private final class FakeEditingUseCase: EditingUseCase, @unchecked Sendable {
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

private final class NoopRecordingUseCase: RecordingUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)

    var state: RecordingState { stateSubject.value }
    var statePublisher: AnyPublisher<RecordingState, Never> { stateSubject.eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { audioLevelSubject.eraseToAnyPublisher() }

    func startRecording() async throws {}
    func stopRecording() async throws {}
    func pauseRecording() {}
    func resumeRecording() {}
    func cancelRecording() {}
    func checkPermission() async -> Bool { true }
    func requestPermission() async -> Bool { true }
}

private final class NoopTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {
    private let liveTextSubject = CurrentValueSubject<String, Never>("")
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private var _currentLanguage: Locale = Locale(identifier: "zh-Hans")

    var liveTextPublisher: AnyPublisher<String, Never> { liveTextSubject.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { finalResultSubject.eraseToAnyPublisher() }
    var currentLanguage: Locale { _currentLanguage }
    var supportedLanguages: [Locale] { [_currentLanguage] }

    func setLanguage(_ locale: Locale) { _currentLanguage = locale }
    func commitCurrentTranscription() async throws {}
    func clearLiveText() {}
}

private final class NoopHistoryUseCase: HistoryUseCase, @unchecked Sendable {
    private let canUndoSubject = CurrentValueSubject<Bool, Never>(false)
    private let canRedoSubject = CurrentValueSubject<Bool, Never>(false)
    private let historyStateSubject = CurrentValueSubject<TextHistoryState, Never>(
        TextHistoryState(currentText: "", canUndo: false, canRedo: false, undoCount: 0, redoCount: 0)
    )

    var canUndo: Bool { false }
    var canRedo: Bool { false }
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
    func cancel() {}
}
