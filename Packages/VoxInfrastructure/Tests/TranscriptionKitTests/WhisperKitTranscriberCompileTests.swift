import TranscriptionKitCombine
import VoxCore
import XCTest
@testable import TranscriptionKit

final class WhisperKitTranscriberCompileTests: XCTestCase {
    func testCanInstantiateWhisperKitTranscriber() {
        _ = CombineTranscriptionCoordinator.wrap(WhisperKitTranscriber(config: LocalWhisperKitConfig(preloadOnStart: false), storageLocations: testStorageLocations))
    }
}
