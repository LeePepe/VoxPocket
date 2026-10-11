import XCTest
import Foundation
import LLMKit
import TranscriptionKit
@testable import UseCases

final class DefaultRefinementUseCaseTests: XCTestCase {
    func testRefineStreamingPassesThroughTranscriptionMetadata() async throws {
        let llm = FakeConsumerLLM()
        let editing = FakeConsumerEditing(text: FakeConsumerContent.input)
        let telemetry = FakeConsumerTelemetry()
        let useCase = DefaultRefinementUseCase(llmService: llm, editing: editing, telemetry: telemetry)
        let metadata = TranscriptionMetadata(
            type: .final, confidence: nil, locale: Locale(identifier: "zh-Hans")
        )
        var chunks: [String] = []
        for try await event in useCase.refineStreaming(
            customPrompt: FakeConsumerContent.prompt, transcriptionMetadata: metadata
        ) {
            if case .chunk(let text) = event { chunks.append(text) }
        }
        XCTAssertEqual(llm.lastRequest?.transcriptionMetadata?.locale?.identifier, "zh-Hans")
        XCTAssertEqual(chunks, [FakeConsumerContent.output])
        XCTAssertEqual(editing.currentText, FakeConsumerContent.input)
        XCTAssertEqual(useCase.state, .completed)
        assertConsumerMetric(telemetry.events, name: "refinement.completed", key: "duration_ms")
        assertConsumerPrivacy(telemetry.events)
    }

    func testNormalAndTranscriptionAwareFailuresKeepErrorsButNotTelemetryContent() async {
        for transcriptionAware in [false, true] {
            for enabled in [true, false] {
                await assertNonStreamingFailure(transcriptionAware: transcriptionAware, enabled: enabled)
            }
        }
    }

    private func assertNonStreamingFailure(transcriptionAware: Bool, enabled: Bool) async {
        let llm = FakeConsumerLLM(outcome: .failure)
        let editing = FakeConsumerEditing(text: FakeConsumerContent.input)
        let telemetry = FakeConsumerTelemetry(isEnabled: enabled)
        let useCase = DefaultRefinementUseCase(llmService: llm, editing: editing, telemetry: telemetry)
        do {
            try await runNonStreaming(useCase, transcriptionAware: transcriptionAware)
            XCTFail("Expected the synthetic business error")
        } catch {
            XCTAssertEqual(error as? FakeConsumerError, .sensitive)
            XCTAssertEqual(useCase.state, .error(FakeConsumerError.sensitive.localizedDescription))
        }
        XCTAssertEqual(editing.currentText, FakeConsumerContent.input)
        XCTAssertEqual(llm.lastRequest?.text, FakeConsumerContent.input)
        XCTAssertEqual(llm.lastRequest?.customPrompt, FakeConsumerContent.prompt)
        XCTAssertEqual(llm.lastRequest?.transcriptionMetadata != nil, transcriptionAware)
        assertFailureTelemetry(telemetry, enabled: enabled)
    }

    func testStreamingFailuresKeepPartialOutputAndErrorsButNotTelemetryContent() async {
        for explicitText in [false, true] {
            for enabled in [true, false] {
                await assertStreamingFailure(explicitText: explicitText, enabled: enabled)
            }
        }
    }

    private func assertStreamingFailure(explicitText: Bool, enabled: Bool) async {
        let llm = FakeConsumerLLM(outcome: .failure)
        let editing = FakeConsumerEditing(text: FakeConsumerContent.input)
        let telemetry = FakeConsumerTelemetry(isEnabled: enabled)
        let useCase = DefaultRefinementUseCase(llmService: llm, editing: editing, telemetry: telemetry)
        var chunks: [String] = []
        do {
            for try await event in stream(useCase, explicitText: explicitText) {
                if case .chunk(let text) = event { chunks.append(text) }
            }
            XCTFail("Expected the synthetic stream error")
        } catch {
            XCTAssertEqual(error as? FakeConsumerError, .sensitive)
            XCTAssertEqual(useCase.state, .error(FakeConsumerError.sensitive.localizedDescription))
        }
        XCTAssertEqual(chunks, [FakeConsumerContent.output])
        XCTAssertEqual(editing.currentText, FakeConsumerContent.input)
        XCTAssertEqual(llm.lastRequest?.text, FakeConsumerContent.input)
        XCTAssertEqual(llm.lastRequest?.customPrompt, FakeConsumerContent.prompt)
        assertFailureTelemetry(telemetry, enabled: enabled)
    }

    func testEditingFailureAlsoKeepsSensitiveErrorOutOfTelemetry() async {
        for transcriptionAware in [false, true] {
            let editing = FakeConsumerEditing(text: FakeConsumerContent.input, replacementError: .sensitive)
            let telemetry = FakeConsumerTelemetry()
            let useCase = DefaultRefinementUseCase(
                llmService: FakeConsumerLLM(), editing: editing, telemetry: telemetry
            )
            do {
                try await runNonStreaming(useCase, transcriptionAware: transcriptionAware)
                XCTFail("Expected editing to fail")
            } catch {
                XCTAssertEqual(error as? FakeConsumerError, .sensitive)
                XCTAssertEqual(useCase.state, .error(FakeConsumerError.sensitive.localizedDescription))
            }
            XCTAssertEqual(editing.currentText, FakeConsumerContent.input)
            assertFailureTelemetry(telemetry, enabled: true)
        }
    }

    func testTaskCancellationPreservesNormalAndTranscriptionAwareErrorContract() async {
        for transcriptionAware in [false, true] {
            let llm = FakeConsumerLLM(outcome: .suspended)
            let editing = FakeConsumerEditing(text: FakeConsumerContent.input)
            let telemetry = FakeConsumerTelemetry()
            let useCase = DefaultRefinementUseCase(llmService: llm, editing: editing, telemetry: telemetry)
            let operation = Task {
                try await runNonStreaming(useCase, transcriptionAware: transcriptionAware)
            }
            defer { llm.release.signal() }
            await llm.started.wait()
            operation.cancel()
            useCase.cancel()
            XCTAssertEqual(useCase.state, .idle)
            llm.release.signal()
            // 非流式现有 catch 仍发送 error 状态和 failed 指标，不把它改成成功或静默丢弃。
            do {
                try await operation.value
                XCTFail("Expected CancellationError")
            } catch {
                XCTAssertTrue(error is CancellationError)
                XCTAssertEqual(useCase.state, .error(error.localizedDescription))
            }
            XCTAssertEqual(llm.cancelCount, 1)
            XCTAssertEqual(editing.currentText, FakeConsumerContent.input)
            assertFailureTelemetry(telemetry, enabled: true)
        }
    }

    func testProviderCancellationErrorInStreamsPreservesFailureContract() async {
        for explicitText in [false, true] {
            let editing = FakeConsumerEditing(text: FakeConsumerContent.input)
            let telemetry = FakeConsumerTelemetry()
            let useCase = DefaultRefinementUseCase(
                llmService: FakeConsumerLLM(outcome: .cancellation), editing: editing, telemetry: telemetry
            )
            do {
                for try await _ in stream(useCase, explicitText: explicitText) {}
                XCTFail("Expected provider CancellationError")
            } catch {
                XCTAssertTrue(error is CancellationError)
                XCTAssertEqual(useCase.state, .error(error.localizedDescription))
            }
            XCTAssertEqual(editing.currentText, FakeConsumerContent.input)
            assertFailureTelemetry(telemetry, enabled: true)
        }
    }

    func testConsumerCancellationTerminatesInnerStreamWithoutTerminalTelemetry() async {
        for explicitText in [false, true] {
            let llm = FakeConsumerLLM(outcome: .suspended)
            let telemetry = FakeConsumerTelemetry()
            let editing = FakeConsumerEditing(text: FakeConsumerContent.input)
            let useCase = DefaultRefinementUseCase(llmService: llm, editing: editing, telemetry: telemetry)
            let events = stream(useCase, explicitText: explicitText)
            let receivedChunk = FakeConsumerSignal()
            let consumer = Task {
                for try await event in events {
                    if case .chunk = event { receivedChunk.signal() }
                }
            }
            await receivedChunk.wait()
            consumer.cancel()
            useCase.cancel()
            _ = await consumer.result
            await llm.streamTerminated.wait()
            XCTAssertEqual(useCase.state, .idle)
            XCTAssertEqual(llm.cancelCount, 1)
            XCTAssertEqual(editing.currentText, FakeConsumerContent.input)
            XCTAssertTrue(telemetry.events.isEmpty)
            assertConsumerPrivacy(telemetry.events)
        }
    }

    func testTranscriptionAwareSuccessPreservesReplacementAndMetadata() async throws {
        let llm = FakeConsumerLLM()
        let editing = FakeConsumerEditing(text: "SYNTHETIC_PREVIOUS_TEXT")
        let telemetry = FakeConsumerTelemetry()
        let useCase = DefaultRefinementUseCase(llmService: llm, editing: editing, telemetry: telemetry)
        try await runNonStreaming(useCase, transcriptionAware: true)
        XCTAssertEqual(editing.currentText, FakeConsumerContent.output)
        XCTAssertEqual(useCase.state, .completed)
        XCTAssertEqual(llm.lastRequest?.text, FakeConsumerContent.input)
        XCTAssertEqual(llm.lastRequest?.transcriptionMetadata?.locale?.identifier, "zh-Hans")
        assertConsumerMetric(telemetry.events, name: "refinement.completed", key: "duration_ms")
        assertConsumerPrivacy(telemetry.events)
    }
}

private func runNonStreaming(_ useCase: DefaultRefinementUseCase, transcriptionAware: Bool) async throws {
    if transcriptionAware {
        let result = TranscriptionResult(
            text: FakeConsumerContent.input, type: .final, locale: Locale(identifier: "zh-Hans")
        )
        try await useCase.refineWithTranscription(result, customPrompt: FakeConsumerContent.prompt)
    } else {
        try await useCase.refine(customPrompt: FakeConsumerContent.prompt)
    }
}

private func stream(
    _ useCase: DefaultRefinementUseCase, explicitText: Bool
) -> AsyncThrowingStream<RefinementEvent, Error> {
    if explicitText {
        return useCase.refineText(FakeConsumerContent.input, customPrompt: FakeConsumerContent.prompt)
    }
    return useCase.refineStreaming(customPrompt: FakeConsumerContent.prompt)
}

private func assertFailureTelemetry(
    _ telemetry: FakeConsumerTelemetry, enabled: Bool, file: StaticString = #filePath, line: UInt = #line
) {
    if enabled {
        assertConsumerMetric(telemetry.events, name: "refinement.failed", key: "duration_ms", file: file, line: line)
    } else {
        XCTAssertTrue(telemetry.events.isEmpty, file: file, line: line)
    }
    assertConsumerPrivacy(telemetry.events, file: file, line: line)
}
