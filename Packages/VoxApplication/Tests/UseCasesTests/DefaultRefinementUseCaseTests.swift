import XCTest
import Combine
import LLMKit
import CoreModels
import TranscriptionKit
@testable import UseCases

final class DefaultRefinementUseCaseTests: XCTestCase {
    func testRefineStreamingPassesThroughTranscriptionMetadata() async throws {
        let llmService = CapturingLLMService()
        let editing = CapturingEditingUseCase(initialText: "再看一下为什么有时候没有能够成功添加标点符号")
        let useCase = DefaultRefinementUseCase(llmService: llmService, editing: editing)

        let metadata = TranscriptionMetadata(
            type: .final,
            confidence: nil,
            locale: Locale(identifier: "zh-Hans")
        )

        let stream = useCase.refineStreaming(customPrompt: nil, transcriptionMetadata: metadata)
        for try await _ in stream {}

        XCTAssertEqual(llmService.lastRefineStreamingRequest?.transcriptionMetadata?.locale?.identifier, "zh-Hans")
    }
}

private final class CapturingLLMService: LLMService, @unchecked Sendable {
    var availableProviders: [LLMProviderType] { [.appleIntelligence] }
    var currentProvider: LLMProvider? { nil }
    var currentProviderType: LLMProviderType? { .appleIntelligence }

    private(set) var lastRefineStreamingRequest: RefinementRequest?

    func setProvider(_ config: LLMProviderConfig) throws {}

    func complete(prompt: String) async throws -> String { "" }

    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        RefinementResponse(
            originalText: request.text,
            refinedText: request.text,
            intentAnalysis: IntentAnalysis(),
            toneAnalysis: ToneAnalysis(),
            missingAnalysisSteps: []
        )
    }

    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        lastRefineStreamingRequest = request
        return AsyncThrowingStream { continuation in
            continuation.yield(request.text)
            continuation.finish()
        }
    }

    func cancel() {}
    func validateCurrentProvider() async -> Bool { true }
}

private final class CapturingEditingUseCase: EditingUseCase, @unchecked Sendable {
    private let currentTextSubject: CurrentValueSubject<String, Never>

    init(initialText: String) {
        self.currentTextSubject = CurrentValueSubject(initialText)
    }

    var currentText: String { currentTextSubject.value }

    var currentTextPublisher: AnyPublisher<String, Never> {
        currentTextSubject.eraseToAnyPublisher()
    }

    func applyEdit(range: CoreModels.TextRange, newText: String) throws {}

    func replaceAll(with text: String) throws {
        currentTextSubject.send(text)
    }

    func insert(_ text: String, at location: Int) throws {}

    func delete(range: CoreModels.TextRange) throws {}

    func append(_ text: String) throws {}

    func mergeRecentEdits() {}

    // MARK: - Voice Zone
    private(set) var voiceAnchorLocation: Int?
    private(set) var isVoiceZoneLocked: Bool = false
    func setVoiceAnchor(_ location: Int) { voiceAnchorLocation = location }
    func clearVoiceAnchor() { voiceAnchorLocation = nil }
    func setVoiceZoneLocked(_ locked: Bool) { isVoiceZoneLocked = locked }
    func replaceVoiceZone(with text: String) throws { currentTextSubject.send(text) }
}
