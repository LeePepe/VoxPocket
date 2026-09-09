import Speech
import XCTest
@testable import TranscriptionKit

final class AppleSpeechRequestFactoryTests: XCTestCase {
    func testRequestEnablesAutomaticPunctuation() {
        let request = DefaultAppleSpeechRequestFactory.makeRequest()

        XCTAssertTrue(request.addsPunctuation)
    }

    func testRequestPreservesLiveResultsAndRecognitionPolicy() {
        let request = DefaultAppleSpeechRequestFactory.makeRequest()

        XCTAssertTrue(request.shouldReportPartialResults)
        XCTAssertFalse(request.requiresOnDeviceRecognition)
    }

    func testRequestsDoNotShareMutableConfiguration() {
        let first = DefaultAppleSpeechRequestFactory.makeRequest()
        first.addsPunctuation = false
        first.shouldReportPartialResults = false

        let second = DefaultAppleSpeechRequestFactory.makeRequest()

        XCTAssertFalse(first === second)
        XCTAssertTrue(second.addsPunctuation)
        XCTAssertTrue(second.shouldReportPartialResults)
    }
}
