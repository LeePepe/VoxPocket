import VoxCore
import XCTest
@testable import VoxSpeechWhisperKit

final class WhisperKitTranscriberCompileTests: XCTestCase {
    func testCanInstantiateWhisperKitTranscriber() {
        _ = AsyncTestCoordinator.wrap(WhisperKitTranscriber(config: LocalWhisperKitConfig(preloadOnStart: false), storageLocations: testStorageLocations))
    }
}
