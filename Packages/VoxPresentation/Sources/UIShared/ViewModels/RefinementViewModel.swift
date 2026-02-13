import Foundation
import Combine
import LLMKit
import UseCases

/// 优化面板 ViewModel
///
/// 桥接 `RefinementUseCase` 到 `RefinementPanelViewState` 协议。
@MainActor
public final class RefinementViewModel: ObservableObject, RefinementPanelViewState {

    // MARK: - 依赖

    private let refinementUseCase: RefinementUseCase
    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?

    // MARK: - Published 状态

    @Published public var customPrompt: String = ""
    @Published public var isRefining: Bool = false
    @Published public var streamingText: String = ""
    @Published public var progressMessage: String = ""
    @Published public var errorMessage: String?
    @Published public var isConfigured: Bool = false

    // MARK: - Init

    public init(refinementUseCase: RefinementUseCase) {
        self.refinementUseCase = refinementUseCase
        self.isConfigured = refinementUseCase.isConfigured

        bindUseCase()
    }

    private func bindUseCase() {
        refinementUseCase.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle:
                    self.isRefining = false
                    self.progressMessage = ""
                case .refining(let progress):
                    self.isRefining = true
                    self.progressMessage = progress
                case .completed:
                    self.isRefining = false
                    self.progressMessage = ""
                    self.streamingText = ""
                case .error(let message):
                    self.isRefining = false
                    self.errorMessage = message
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 操作

    public func refine() async {
        do {
            let prompt = customPrompt.isEmpty ? nil : customPrompt
            try await refinementUseCase.refine(customPrompt: prompt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refineSelection(range: NSRange) async {
        do {
            let prompt = customPrompt.isEmpty ? nil : customPrompt
            try await refinementUseCase.refineSelection(
                range: range,
                customPrompt: prompt
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refineWithStreaming() async {
        streamingTask?.cancel()
        streamingText = ""

        let prompt = customPrompt.isEmpty ? nil : customPrompt
        let stream = refinementUseCase.refineStreaming(
            customPrompt: prompt
        )

        streamingTask = Task {
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .chunk(let text):
                        // chunk 是累积的完整文本，直接替换
                        streamingText = text
                    case .state(let state):
                        // 状态已经通过 statePublisher 自动同步，这里可以忽略
                        // 如果需要特殊处理，可以在这里添加
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
        refinementUseCase.cancel()
    }

    public func clearError() {
        errorMessage = nil
    }
}
