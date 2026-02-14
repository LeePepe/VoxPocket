import XCTest
import Combine
import CoreModels
import LLMKit
@testable import UIShared

@MainActor
final class RootViewModelTests: XCTestCase {
    func testInitTriggersHistoryLoad() async {
        let sessionList = SessionListSpy()
        let editor = EditorStateSpy()

        _ = RootViewModel(sessionListState: sessionList, editorState: editor)
        await Task.yield()

        XCTAssertEqual(sessionList.loadSessionsCallCount, 1)
    }

    func testSelectSessionDelegatesToSessionListState() async {
        let sessionList = SessionListSpy()
        let editor = EditorStateSpy()
        let root = RootViewModel(sessionListState: sessionList, editorState: editor)
        let id = UUID()

        root.selectSession(id)
        await Task.yield()

        XCTAssertEqual(sessionList.selectSessionCallCount, 1)
        XCTAssertEqual(sessionList.selectedSessionId, id)
        XCTAssertFalse(root.isDrawerOpen)
    }
}

@MainActor
private final class SessionListSpy: ObservableObject, SessionListViewState {
    @Published var sessions: [Session] = []
    @Published var isLoading: Bool = false
    @Published var selectedSessionId: UUID?
    @Published var searchQuery: String = ""
    @Published var errorMessage: String?

    private(set) var loadSessionsCallCount = 0
    private(set) var selectSessionCallCount = 0

    var filteredSessions: [Session] { sessions }

    func loadSessions() async {
        loadSessionsCallCount += 1
    }

    func createSession() async {}
    func deleteSession(_ id: UUID) async {}
    func deleteAllSessions() async {}
    func refresh() async {}
    func clearError() {}

    func selectSession(_ id: UUID) async {
        selectSessionCallCount += 1
        selectedSessionId = id
    }
}

@MainActor
private final class EditorStateSpy: ObservableObject, EditorViewState {
    @Published var text: String = ""
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var liveTranscription: String = ""
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    @Published var isRefining: Bool = false
    @Published var errorMessage: String?
    @Published var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @Published var rawTranscription: String = ""
    @Published var streamingRefinedText: String = ""
    @Published var autoCopiedText: String?

    func startRecording() async {}
    func stopRecording() async {}
    func toggleRecording() async {}
    func startNewSession() async {}
    func undo() {}
    func redo() {}
    func updateText(_ newText: String, range: NSRange) {}
    func refine() async {}
    func cancelRefinement() {}
    func clearError() {}
    func clearText() {}
}
