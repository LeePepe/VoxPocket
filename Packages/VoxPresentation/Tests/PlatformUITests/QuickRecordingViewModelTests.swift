#if os(macOS)
import XCTest
import Combine
import PlatformAdapters
import TranscriptionKit
import UseCases
@testable import PlatformUI

@MainActor
final class QuickRecordingViewModelTests: XCTestCase {
    func testQuickRecordingDoesNotAutoStopAfterSilenceWhileStillHeld() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        await viewModel.startRecording()
        transcription.sendLiveText("你好")

        try? await Task.sleep(nanoseconds: 3_100_000_000)

        XCTAssertEqual(recording.stopCallCount, 0)
        XCTAssertEqual(viewModel.recorderStatus, .listening)
    }

    func testStopRecordingUsesLatestTranscriptionArrivingRightAfterStop() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        recording.onStop = {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                transcription.sendLiveText("你好世界")
                try? await Task.sleep(nanoseconds: 80_000_000)
                transcription.sendLifecycleEvent(.recognitionCompleted)
            }
        }

        await viewModel.startRecording()
        transcription.sendLiveText("你好世")

        await viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertEqual(viewModel.rawTranscription, "你好世界")
    }

    func testStopRecordingWaitsForDelayedFinalTranscription() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        recording.onStop = {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                transcription.sendFinalText("你好世界")
                transcription.sendLifecycleEvent(.recognitionCompleted)
            }
        }

        await viewModel.startRecording()
        transcription.sendLiveText("你好世")

        await viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertEqual(viewModel.rawTranscription, "你好世界")
    }

    func testStopRecordingWaitsForRecognitionCompletedBeforeContinuing() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        await viewModel.startRecording()
        transcription.sendLiveText("你好世界")

        let stopTask = Task {
            await viewModel.stopRecording()
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertEqual(viewModel.recorderStatus, .transcribing)
        XCTAssertEqual(viewModel.rawTranscription, "")

        transcription.sendLifecycleEvent(.recognitionCompleted)
        await stopTask.value

        XCTAssertEqual(viewModel.rawTranscription, "你好世界")
    }

    func testStopRecordingFallsBackAfterRecognitionCompletionTimeout() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        await viewModel.startRecording()
        transcription.sendLiveText("你好世界")

        let stopTask = Task {
            await viewModel.stopRecording()
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(viewModel.recorderStatus, .transcribing)
        XCTAssertEqual(viewModel.rawTranscription, "")

        await stopTask.value

        XCTAssertEqual(viewModel.rawTranscription, "你好世界")
    }

    func testStopRecordingWithEmptyTranscriptionTriggersNoResultCallback() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        var didCallNoResult = false
        viewModel.onNoResult = {
            didCallNoResult = true
        }

        recording.onStop = {
            Task { @MainActor in
                transcription.sendLifecycleEvent(.recognitionCompleted)
            }
        }

        await viewModel.startRecording()
        await viewModel.stopRecording()

        XCTAssertTrue(didCallNoResult)
    }

    func testStopRequestedDuringStartStopsAfterStartCompletes() async {
        let recording = FakeRecordingUseCase(startDelayNanoseconds: 300_000_000)
        let transcription = FakeTranscriptionUseCase()
        let refinement = FakeRefinementUseCase()
        let clipboard = FakeClipboardService()
        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard
        )

        let startTask = Task {
            await viewModel.startRecording()
        }
        await Task.yield()
        recording.onStop = {
            Task { @MainActor in
                transcription.sendLifecycleEvent(.recognitionCompleted)
            }
        }
        await viewModel.stopRecording()
        await startTask.value

        XCTAssertEqual(recording.stopCallCount, 1)
    }
}

private final class FakeRecordingUseCase: RecordingUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let levelSubject = CurrentValueSubject<Float, Never>(0)
    private let startDelayNanoseconds: UInt64
    private(set) var stopCallCount = 0
    var onStop: (() -> Void)?

    init(startDelayNanoseconds: UInt64 = 0) {
        self.startDelayNanoseconds = startDelayNanoseconds
    }

    var state: RecordingState { stateSubject.value }
    var statePublisher: AnyPublisher<RecordingState, Never> { stateSubject.eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }

    func startRecording() async throws {
        if startDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: startDelayNanoseconds)
        }
        stateSubject.send(.recording(duration: 0))
    }

    func stopRecording() async throws {
        stopCallCount += 1
        onStop?()
        stateSubject.send(.idle)
    }

    func pauseRecording() { stateSubject.send(.paused(duration: 0)) }
    func resumeRecording() { stateSubject.send(.recording(duration: 0)) }
    func cancelRecording() { stateSubject.send(.idle) }
    func checkPermission() async -> Bool { true }
    func requestPermission() async -> Bool { true }
}

private final class FakeTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {
    private let liveTextSubject = CurrentValueSubject<String, Never>("")
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let lifecycleEventSubject = PassthroughSubject<TranscriptionLifecycleEvent, Never>()
    private var _currentLanguage = Locale(identifier: "zh-Hans")

    var liveTextPublisher: AnyPublisher<String, Never> { liveTextSubject.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { finalResultSubject.eraseToAnyPublisher() }
    var lifecycleEventPublisher: AnyPublisher<TranscriptionLifecycleEvent, Never> { lifecycleEventSubject.eraseToAnyPublisher() }
    var currentLanguage: Locale { _currentLanguage }
    var supportedLanguages: [Locale] { [_currentLanguage] }

    func setLanguage(_ locale: Locale) { _currentLanguage = locale }
    func commitCurrentTranscription() async throws {}
    func clearLiveText() { liveTextSubject.send("") }
    func sendLiveText(_ text: String) { liveTextSubject.send(text) }
    func sendFinalText(_ text: String) {
        finalResultSubject.send(
            TranscriptionResult(
                text: text,
                type: .final,
                confidence: nil,
                timestamp: Date(),
                locale: _currentLanguage
            )
        )
    }
    func sendLifecycleEvent(_ event: TranscriptionLifecycleEvent) { lifecycleEventSubject.send(event) }
}

private final class FakeRefinementUseCase: RefinementUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RefinementState, Never>(.idle)

    var state: RefinementState { stateSubject.value }
    var statePublisher: AnyPublisher<RefinementState, Never> { stateSubject.eraseToAnyPublisher() }
    var isConfigured: Bool { true }

    func refine(customPrompt: String?) async throws {}
    func refineSelection(range: NSRange, customPrompt: String?) async throws {}
    func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
    func cancel() { stateSubject.send(.idle) }
}

private final class FakeClipboardService: ClipboardService, @unchecked Sendable {
    var hasText: Bool { false }
    func copy(_ text: String) {}
    func paste() -> String? { nil }
    func clear() {}
    func simulatePaste() async throws {}
}
#endif
