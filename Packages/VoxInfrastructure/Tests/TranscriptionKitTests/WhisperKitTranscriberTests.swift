import XCTest
@testable import TranscriptionKit

final class WhisperKitTranscriberTests: XCTestCase {
    func testCanInstantiateWhisperKitTranscriber() {
        _ = WhisperKitTranscriber()
    }

    func testProviderTypeIsWhisper() {
        let sut = WhisperKitTranscriber()
        XCTAssertEqual(sut.speechRecognitionService.providerType, .whisper)
    }
}
