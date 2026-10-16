import Combine
import CoreModels
import Foundation
import LLMKit
import LokiKit
import Synchronization
import TranscriptionKit
import XCTest
@testable import UseCases

final class DefaultRefinementTelemetryPrivacyTests: XCTestCase {
    func testAllFailurePathsKeepErrorsOutOfTelemetryWhilePreservingPropagation() async {
        let telemetry = CapturingRefinementTelemetry()
        let editing = RefinementPrivacyEditingUseCase(initialText: PrivateSentinel.transcript)
        let useCase = DefaultRefinementUseCase(
            llmService: FailingRefinementLLMService(),
            editing: editing,
            telemetry: telemetry
        )

        await assertPrivateFailure {
            try await useCase.refine(customPrompt: PrivateSentinel.prompt)
        }
        assertErrorStatePreservesDomainMessage(useCase.state)

        await assertPrivateFailure {
            for try await _ in useCase.refineStreaming(customPrompt: PrivateSentinel.prompt) {}
        }
        assertErrorStatePreservesDomainMessage(useCase.state)

        await assertPrivateFailure {
            for try await _ in useCase.refineText(
                PrivateSentinel.refinedText,
                customPrompt: PrivateSentinel.prompt
            ) {}
        }
        assertErrorStatePreservesDomainMessage(useCase.state)

        let transcription = TranscriptionResult(
            text: PrivateSentinel.transcript,
            type: .final,
            confidence: nil,
            timestamp: Date(),
            locale: Locale(identifier: "zh-Hans")
        )
        await assertPrivateFailure {
            try await useCase.refineWithTranscription(
                transcription,
                customPrompt: PrivateSentinel.prompt
            )
        }
        assertErrorStatePreservesDomainMessage(useCase.state)

        let events = telemetry.events
        XCTAssertEqual(events.count, 4)
        for event in events {
            XCTAssertEqual(event.name, VoxPocketTelemetryEventName.refinementFailed.rawValue)
            XCTAssertEqual(Set(event.properties.keys), ["duration_ms"])
            XCTAssertNotNil(event.properties["duration_ms"].flatMap(Int.init))
            XCTAssertTrue(PrivateSentinel.all.allSatisfy { marker in
                event.properties.allSatisfy { key, value in
                    !key.contains(marker) && !value.contains(marker)
                }
            })
        }
    }

    private func assertPrivateFailure(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected refinement to fail", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? RefinementPrivacyError, .privateContent, file: file, line: line)
        }
    }

    private func assertErrorStatePreservesDomainMessage(
        _ state: RefinementState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .error(let message) = state else {
            return XCTFail("Expected error state", file: file, line: line)
        }
        XCTAssertEqual(message, RefinementPrivacyError.privateContent.localizedDescription, file: file, line: line)
    }
}

private enum PrivateSentinel {
    static let transcript = "PRIVATE_TRANSCRIPT_SENTINEL"
    static let refinedText = "PRIVATE_REFINED_TEXT_SENTINEL"
    static let prompt = "PRIVATE_PROMPT_SENTINEL"
    static let audio = "PRIVATE_AUDIO_SENTINEL"
    static let endpoint = "https://private-endpoint.invalid"
    static let sas = "PRIVATE_SAS_SENTINEL"
    static let credential = "PRIVATE_CREDENTIAL_SENTINEL"

    static let all = [transcript, refinedText, prompt, audio, endpoint, sas, credential]
}

private enum RefinementPrivacyError: LocalizedError {
    case privateContent

    var errorDescription: String? {
        PrivateSentinel.all.joined(separator: "|")
    }
}

private final class FailingRefinementLLMService: LLMService {
    var availableProviders: [LLMProviderType] { [.appleIntelligence] }
    var currentProvider: LLMProvider? { nil }
    var currentProviderType: LLMProviderType? { .appleIntelligence }

    func setProvider(_ config: LLMProviderConfig) throws {}

    func complete(prompt: String) async throws -> String {
        throw RefinementPrivacyError.privateContent
    }

    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        throw RefinementPrivacyError.privateContent
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        throw RefinementPrivacyError.privateContent
    }

    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        throw RefinementPrivacyError.privateContent
    }

    func cancel() {}

    func validateCurrentProvider() async -> Bool { true }
}

// CurrentValueSubject provides the synchronous Combine bridge required by EditingUseCase.
private final class RefinementPrivacyEditingUseCase: EditingUseCase, @unchecked Sendable {
    private let text: CurrentValueSubject<String, Never>

    init(initialText: String) {
        text = CurrentValueSubject(initialText)
    }

    var currentText: String { text.value }

    var currentTextPublisher: AnyPublisher<String, Never> {
        text.eraseToAnyPublisher()
    }

    func applyEdit(range: CoreModels.TextRange, newText: String) throws {}
    func replaceAll(with text: String) throws { self.text.send(text) }
    func insert(_ text: String, at location: Int) throws {}
    func delete(range: CoreModels.TextRange) throws {}
    func append(_ text: String) throws {}
    func mergeRecentEdits() {}

    private(set) var voiceAnchorLocation: Int?
    private(set) var isVoiceZoneLocked = false

    func setVoiceAnchor(_ location: Int) { voiceAnchorLocation = location }
    func clearVoiceAnchor() { voiceAnchorLocation = nil }
    func setVoiceZoneLocked(_ locked: Bool) { isVoiceZoneLocked = locked }
    func replaceVoiceZone(with text: String) throws { self.text.send(text) }
}

private final class CapturingRefinementTelemetry: TelemetryService {
    private struct State {
        var isEnabled = true
        var events: [TelemetryEvent] = []
    }

    private let state = Mutex(State())

    var isEnabled: Bool {
        get { state.withLock { $0.isEnabled } }
        set { state.withLock { $0.isEnabled = newValue } }
    }

    var events: [TelemetryEvent] {
        state.withLock { $0.events }
    }

    func track(_ event: TelemetryEvent) {
        state.withLock { $0.events.append(event) }
    }

    func track(name: String, properties: [String: String]) {
        track(TelemetryEvent(name: name, properties: properties))
    }

    func flush() async {}
    func resetIdentifier() {}
}
