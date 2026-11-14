import Foundation
import Combine
import CoreModels
import VoxLLM

/// Preview 用 Mock 编辑器 ViewModel
@MainActor
public final class MockEditorViewModel: ObservableObject, EditorViewState {

    @Published public var text: String
    @Published public var isRecording: Bool = false
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var audioLevel: Float = 0
    @Published public var liveTranscription: String = ""
    @Published public var canUndo: Bool = false
    @Published public var canRedo: Bool = false
    @Published public var isRefining: Bool = false
    @Published public var errorMessage: String?
    @Published public var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @Published public var rawTranscription: String = ""
    @Published public var streamingRefinedText: String = ""
    @Published public var autoCopiedText: String?
    @Published public var isVoiceZoneEditing: Bool = false

    private var mockTask: Task<Void, Never>?

    public init(text: String = "周五产品评审结论：首屏彻底去掉顶部状态胶囊，只保留中央一句话与底部液态玻璃底座。") {
        self.text = text
    }

    public func startRecording() async {
        cancelMockFlow()
        rawTranscription = ""
        streamingRefinedText = ""
        isRefining = false
        isRecording = true
        liveTranscription = "把刚才散步想到的播客开场白记一下，先从一个深夜收到听众来信的故事切入"
    }

    public func stopRecording() async {
        mockTask?.cancel()
        mockTask = nil
        isRecording = false
        rawTranscription = liveTranscription
        text = rawTranscription
        await refine()
    }

    public func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    public func refine() async {
        isRefining = true
        streamingRefinedText = ""
        let chunks = ["播客开场灵感：", "从一封深夜收到的听众来信切入，", "顺势引出本期关于「慢下来思考」", "的核心主题。"]
        for chunk in chunks {
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { isRefining = false; return }
            guard !Task.isCancelled else { isRefining = false; return }
            streamingRefinedText += chunk
        }
        guard !Task.isCancelled else { isRefining = false; return }
        text = streamingRefinedText
        isRefining = false
    }

    public func cancelRefinement() {
        cancelMockFlow()
        isRefining = false
        streamingRefinedText = ""
    }

    public func undo() {
        canUndo = false
        canRedo = true
    }

    public func redo() {
        canUndo = true
        canRedo = false
    }

    public func updateText(_ newText: String, range: NSRange) {
        text = newText
        canUndo = true
    }

    public func clearError() {
        errorMessage = nil
    }

    public func clearText() {
        text = ""
        rawTranscription = ""
        streamingRefinedText = ""
    }

    public func startNewSession() async {
        clearText()
        await startRecording()
    }

    private func cancelMockFlow() {
        mockTask?.cancel()
        mockTask = nil
    }
}
