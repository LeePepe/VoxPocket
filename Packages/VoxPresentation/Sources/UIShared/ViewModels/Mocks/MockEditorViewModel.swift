import Foundation
import Combine
import CoreModels
import LLMKit

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

    private var mockTask: Task<Void, Never>?

    public init(text: String = "立刻记录：客户反馈集中在首屏加载速度与登录重试。") {
        self.text = text
    }

    public func startRecording() async {
        cancelMockFlow()
        rawTranscription = ""
        streamingRefinedText = ""

        mockTask = Task { @MainActor in
            isRecording = true
            liveTranscription = "正在识别语音..."
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }

            // 模拟录音结束
            isRecording = false
            rawTranscription = "客户反馈集中在首屏加载速度与登录重试"
            text = rawTranscription

            // 模拟 refine 流式输出
            isRefining = true
            let chunks = ["客户", "反馈主要", "集中在两个方面：", "首屏加载速度", "较慢，", "以及登录", "重试体验", "不佳。"]
            for chunk in chunks {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                streamingRefinedText += chunk
            }
            text = streamingRefinedText
            isRefining = false
        }
    }

    public func stopRecording() async {
        cancelMockFlow()
        isRecording = false
        isRefining = false
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
        let chunks = ["这是", "优化后", "的文本", "示例。"]
        for chunk in chunks {
            try? await Task.sleep(nanoseconds: 300_000_000)
            streamingRefinedText += chunk
        }
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

    private func cancelMockFlow() {
        mockTask?.cancel()
        mockTask = nil
    }
}
