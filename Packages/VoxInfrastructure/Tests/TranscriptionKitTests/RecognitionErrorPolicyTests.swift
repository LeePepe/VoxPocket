import XCTest
@testable import TranscriptionKit

final class RecognitionErrorPolicyTests: XCTestCase {
    func testRecoverableRecognitionErrorClassification() {
        let recoverable = NSError(domain: "kAFAssistantErrorDomain", code: 216, userInfo: nil)
        let nonRecoverable = NSError(domain: "SFSpeechRecognizerErrorDomain", code: 1, userInfo: nil)

        XCTAssertTrue(AppleSpeechTranscriber.shouldSuppressLiveStreamCompletion(for: recoverable, isStopping: false))
        XCTAssertFalse(AppleSpeechTranscriber.shouldSuppressLiveStreamCompletion(for: nonRecoverable, isStopping: false))
    }

    func testSuppressesCompletionWhileStopping() {
        let error = NSError(domain: "SFSpeechRecognizerErrorDomain", code: 1, userInfo: nil)

        XCTAssertTrue(AppleSpeechTranscriber.shouldSuppressLiveStreamCompletion(for: error, isStopping: true))
    }
}
