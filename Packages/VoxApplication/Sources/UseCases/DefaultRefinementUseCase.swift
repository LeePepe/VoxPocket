import Foundation
import Combine
import LLMKit
import CoreModels
import TranscriptionKit
import Observability

/// LLM 优化用例默认实现
///
/// 桥接 `LLMService` 到 `RefinementUseCase` 协议。
/// 读取当前文本，调用 LLM 优化，将结果提交到编辑历史。
public final class DefaultRefinementUseCase: @unchecked Sendable {

    private let llmService: LLMService
    private let editingUseCase: EditingUseCase
    private let telemetry: any TelemetryService

    private let stateSubject = CurrentValueSubject<RefinementState, Never>(.idle)

    public init(llmService: LLMService, editing: EditingUseCase, telemetry: any TelemetryService = NoopTelemetryService()) {
        self.llmService = llmService
        self.editingUseCase = editing
        self.telemetry = telemetry
    }
}

// MARK: - RefinementUseCase

extension DefaultRefinementUseCase: RefinementUseCase {

    public var state: RefinementState {
        stateSubject.value
    }

    public var statePublisher: AnyPublisher<RefinementState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public var isConfigured: Bool {
        llmService.currentProvider != nil
    }

    public func refine(customPrompt: String?) async throws {
        let text = editingUseCase.currentText
        guard !text.isEmpty else { return }

        let startTime = Date()
        stateSubject.send(.refining(progress: "处理中..."))

        do {
            let request = RefinementRequest(text: text, customPrompt: customPrompt)
            let response = try await llmService.refine(request)
            try editingUseCase.replaceAll(with: response.refinedText)
            stateSubject.send(.completed)
            telemetry.track(name: TelemetryEventName.refinementCompleted.rawValue, properties: [
                "duration_ms": String(Int(Date().timeIntervalSince(startTime) * 1000))
            ])
        } catch {
            stateSubject.send(.error(error.localizedDescription))
            telemetry.track(name: TelemetryEventName.refinementFailed.rawValue, properties: [
                "duration_ms": String(Int(Date().timeIntervalSince(startTime) * 1000)),
                "error": error.localizedDescription
            ])
            throw error
        }
    }

    public func refineSelection(range: NSRange, customPrompt: String?) async throws {
        let fullText = editingUseCase.currentText
        guard let swiftRange = Range(range, in: fullText) else { return }

        let selectedText = String(fullText[swiftRange])
        guard !selectedText.isEmpty else { return }

        stateSubject.send(.refining(progress: "处理中..."))

        do {
            let request = RefinementRequest(text: selectedText, customPrompt: customPrompt)
            let response = try await llmService.refine(request)
            let textRange = CoreModels.TextRange(location: range.location, length: range.length)
            try editingUseCase.applyEdit(range: textRange, newText: response.refinedText)
            stateSubject.send(.completed)
        } catch {
            stateSubject.send(.error(error.localizedDescription))
            throw error
        }
    }

    public func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        refineStreaming(customPrompt: customPrompt, transcriptionMetadata: nil)
    }

    public func refineStreaming(
        customPrompt: String?,
        transcriptionMetadata: TranscriptionMetadata?
    ) -> AsyncThrowingStream<RefinementEvent, Error> {
        let text = editingUseCase.currentText
        guard !text.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }

        let request = RefinementRequest(
            text: text,
            customPrompt: customPrompt,
            transcriptionMetadata: transcriptionMetadata
        )
        nonisolated(unsafe) let stateSubject = self.stateSubject
        let llmService = self.llmService

        let telemetry = self.telemetry

        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                // 发送开始状态
                let startTime = Date()
                let refiningState = RefinementState.refining(progress: "处理中...")
                stateSubject.send(refiningState)
                continuation.yield(.state(refiningState))

                do {
                    // 获取流式响应
                    let innerStream = try await llmService.refineStreaming(request)

                    // 发送文本块
                    for try await chunk in innerStream {
                        guard !Task.isCancelled else { break }
                        continuation.yield(.chunk(chunk))
                    }

                    // 发送完成状态
                    if !Task.isCancelled {
                        stateSubject.send(.completed)
                        continuation.yield(.state(.completed))
                        telemetry.track(name: TelemetryEventName.refinementCompleted.rawValue, properties: [
                            "duration_ms": String(Int(Date().timeIntervalSince(startTime) * 1000))
                        ])
                    }
                    continuation.finish()
                } catch {
                    // 发送错误状态
                    if !Task.isCancelled {
                        let errorState = RefinementState.error(error.localizedDescription)
                        stateSubject.send(errorState)
                        telemetry.track(name: TelemetryEventName.refinementFailed.rawValue, properties: [
                            "duration_ms": String(Int(Date().timeIntervalSince(startTime) * 1000)),
                            "error": error.localizedDescription
                        ])
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func refineText(_ text: String, customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        guard !text.isEmpty else {
            return AsyncThrowingStream { $0.finish() }
        }

        let request = RefinementRequest(text: text, customPrompt: customPrompt)
        nonisolated(unsafe) let stateSubject = self.stateSubject
        let llmService = self.llmService
        let telemetry = self.telemetry

        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                let startTime = Date()
                let refiningState = RefinementState.refining(progress: "处理中...")
                stateSubject.send(refiningState)
                continuation.yield(.state(refiningState))

                do {
                    let innerStream = try await llmService.refineStreaming(request)
                    for try await chunk in innerStream {
                        guard !Task.isCancelled else { break }
                        continuation.yield(.chunk(chunk))
                    }
                    if !Task.isCancelled {
                        stateSubject.send(.completed)
                        continuation.yield(.state(.completed))
                        telemetry.track(name: TelemetryEventName.refinementCompleted.rawValue, properties: [
                            "duration_ms": String(Int(Date().timeIntervalSince(startTime) * 1000))
                        ])
                    }
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        let errorState = RefinementState.error(error.localizedDescription)
                        stateSubject.send(errorState)
                        telemetry.track(name: TelemetryEventName.refinementFailed.rawValue, properties: [
                            "duration_ms": String(Int(Date().timeIntervalSince(startTime) * 1000)),
                            "error": error.localizedDescription
                        ])
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func cancel() {
        llmService.cancel()
        stateSubject.send(.idle)
    }

    // MARK: - Transcription-Aware Refinement

    /// 基于 TranscriptionResult 进行优化（包含元数据）
    ///
    /// 此方法接收完整的 TranscriptionResult，提取元数据传递给 LLM，
    /// 以支持内容分析和上下文感知的优化。
    ///
    /// - Parameters:
    ///   - result: 转录结果（包含文本、类型、置信度等）
    ///   - customPrompt: 可选的自定义提示词
    public func refineWithTranscription(
        _ result: TranscriptionResult,
        customPrompt: String? = nil
    ) async throws {
        guard !result.text.isEmpty else { return }

        let startTime = Date()
        let progressMessage = result.isFinal ? "分析语音内容..." : "处理中..."
        stateSubject.send(.refining(progress: progressMessage))

        do {
            let metadata = TranscriptionMetadata(from: result)
            let request = RefinementRequest(
                text: result.text,
                customPrompt: customPrompt,
                transcriptionMetadata: metadata
            )

            let response = try await llmService.refine(request)

            try editingUseCase.replaceAll(with: response.refinedText)
            stateSubject.send(.completed)
            telemetry.track(name: TelemetryEventName.refinementCompleted.rawValue, properties: [
                "duration_ms": String(Int(Date().timeIntervalSince(startTime) * 1000))
            ])
        } catch {
            stateSubject.send(.error(error.localizedDescription))
            telemetry.track(name: TelemetryEventName.refinementFailed.rawValue, properties: [
                "duration_ms": String(Int(Date().timeIntervalSince(startTime) * 1000)),
                "error": error.localizedDescription
            ])
            throw error
        }
    }
}
