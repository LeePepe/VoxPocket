import Foundation
import Combine
import LLMKit

/// Preview 用 Mock 优化面板 ViewModel
@MainActor
public final class MockRefinementViewModel: ObservableObject, RefinementPanelViewState {

    @Published public var customPrompt: String = ""
    @Published public var isRefining: Bool = false
    @Published public var streamingText: String = ""
    @Published public var progressMessage: String = ""
    @Published public var errorMessage: String?
    @Published public var isConfigured: Bool = true

    public init() {}

    public func refine() async {
        isRefining = true
        progressMessage = "优化中..."
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        isRefining = false
        progressMessage = ""
    }

    public func refineSelection(range: NSRange) async {
        await refine()
    }

    public func refineWithStreaming() async {
        isRefining = true
        let chunks = ["这是", "优化后", "的文本", "示例。"]
        for chunk in chunks {
            try? await Task.sleep(nanoseconds: 300_000_000)
            streamingText += chunk
        }
        isRefining = false
    }

    public func cancel() {
        isRefining = false
        streamingText = ""
    }

    public func clearError() {
        errorMessage = nil
    }
}
