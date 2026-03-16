#if os(macOS)
import XCTest
import Combine
import PlatformAdapters
import TranscriptionKit
import UseCases
@testable import PlatformUI

@MainActor
final class QuickRecordingViewModelTests: XCTestCase {
    func testShowsLiveTranscriptionOnlyForDisplayableStatesWithText() async {
        let viewModel = makeViewModel()

        viewModel.liveTranscription = ""
        viewModel.recorderStatus = .listening
        XCTAssertFalse(viewModel.showsLiveTranscription)

        viewModel.liveTranscription = "你好"
        viewModel.recorderStatus = .listening
        XCTAssertTrue(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .transcribing
        XCTAssertTrue(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .refining
        XCTAssertTrue(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .idle
        XCTAssertFalse(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .done
        XCTAssertFalse(viewModel.showsLiveTranscription)

        viewModel.recorderStatus = .error
        XCTAssertFalse(viewModel.showsLiveTranscription)
    }

    func testStopRecordingRetainsLiveTranscriptionForProcessingStates() async {
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
        transcription.sendLiveText("实时转写尾部")

        await viewModel.stopRecording()

        XCTAssertEqual(viewModel.liveTranscription, "实时转写尾部")
        XCTAssertTrue(viewModel.showsLiveTranscription)
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
            }
        }

        await viewModel.startRecording()
        transcription.sendLiveText("你好世")

        await viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 160_000_000)

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
        await viewModel.stopRecording()
        await startTask.value

        XCTAssertEqual(recording.stopCallCount, 1)
    }

    private func makeViewModel() -> QuickRecordingViewModel {
        QuickRecordingViewModel(
            recordingUseCase: FakeRecordingUseCase(),
            transcriptionUseCase: FakeTranscriptionUseCase(),
            refinementUseCase: FakeRefinementUseCase(),
            clipboardService: FakeClipboardService()
        )
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
    private var _currentLanguage = Locale(identifier: "zh-Hans")

    var liveTextPublisher: AnyPublisher<String, Never> { liveTextSubject.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { finalResultSubject.eraseToAnyPublisher() }
    var currentLanguage: Locale { _currentLanguage }
    var supportedLanguages: [Locale] { [_currentLanguage] }

    func setLanguage(_ locale: Locale) { _currentLanguage = locale }
    func commitCurrentTranscription() async throws {}
    func clearLiveText() { liveTextSubject.send("") }
    func sendLiveText(_ text: String) { liveTextSubject.send(text) }
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
