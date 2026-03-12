import XCTest
@testable import TranscriptionKit

final class WhisperKitTranscriberCompileTests: XCTestCase {
    func testCanInstantiateWhisperKitTranscriber() {
        _ = WhisperKitTranscriber(config: LocalWhisperKitConfig(preloadOnStart: false))
    }
}
