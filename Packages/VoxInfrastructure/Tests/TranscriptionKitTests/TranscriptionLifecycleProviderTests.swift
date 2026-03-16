import Combine
import Foundation
import XCTest
@testable import TranscriptionKit

final class TranscriptionLifecycleProviderTests: XCTestCase {
    func testAppleSpeechPublishesSpeechDetectedOnlyOnce() {
        let sut = AppleSpeechTranscriber(locale: Locale(identifier: "zh-Hans"))

        var events: [TranscriptionLifecycleEvent] = []
        let cancellable = sut.lifecycleEventPublisher.sink { events.append($0) }
        defer { cancellable.cancel() }

        sut.handleRecognitionResultForTesting(
            text: "你好",
            isFinal: false,
            confidence: nil,
            locale: Locale(identifier: "zh-Hans")
        )
        sut.handleRecognitionResultForTesting(
            text: "你好世界",
            isFinal: false,
            confidence: nil,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(events.filter { $0 == .speechDetected }.count, 1)
    }

    func testAppleSpeechPublishesRecognitionCompletedOnFinalResult() {
        let sut = AppleSpeechTranscriber(locale: Locale(identifier: "zh-Hans"))

        var events: [TranscriptionLifecycleEvent] = []
        let cancellable = sut.lifecycleEventPublisher.sink { events.append($0) }
        defer { cancellable.cancel() }

        sut.handleRecognitionResultForTesting(
            text: "你好世界",
            isFinal: true,
            confidence: 0.9,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(events.suffix(2), [.speechDetected, .recognitionCompleted])
    }

    func testHybridPublishesSpeechDetectedOnlyOnce() {
        let sut = HybridWhisperTranscriber(
            whisperConfig: AzureWhisperConfig(
                endpoint: URL(string: "https://example.com")!,
                apiKey: "test"
            )
        )

        var events: [TranscriptionLifecycleEvent] = []
        let cancellable = sut.lifecycleEventPublisher.sink { events.append($0) }
        defer { cancellable.cancel() }

        sut.handleAppleRecognitionTextForTesting(
            "你好",
            isFinal: false,
            locale: Locale(identifier: "zh-Hans")
        )
        sut.handleAppleRecognitionTextForTesting(
            "你好世界",
            isFinal: false,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(events.filter { $0 == .speechDetected }.count, 1)
    }

    func testHybridPublishesRecognitionCompletedWhenWhisperStageFinishes() {
        let sut = HybridWhisperTranscriber(
            whisperConfig: AzureWhisperConfig(
                endpoint: URL(string: "https://example.com")!,
                apiKey: "test"
            )
        )

        var events: [TranscriptionLifecycleEvent] = []
        let cancellable = sut.lifecycleEventPublisher.sink { events.append($0) }
        defer { cancellable.cancel() }

        sut.publishWhisperCompletionForTesting(
            text: "你好世界",
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(events.last, .recognitionCompleted)
    }

    func testAzurePublishesSilenceDetectedAndRecognitionCompleted() {
        let sut = AzureWhisperTranscriber(
            config: AzureWhisperConfig(
                endpoint: URL(string: "https://example.com")!,
                apiKey: "test"
            )
        )

        var events: [TranscriptionLifecycleEvent] = []
        let cancellable = sut.lifecycleEventPublisher.sink { events.append($0) }
        defer { cancellable.cancel() }

        sut.publishSilenceDetectedForTesting()
        sut.publishRecognitionCompletedForTesting()

        XCTAssertEqual(events, [.silenceDetected, .recognitionCompleted])
    }
}
