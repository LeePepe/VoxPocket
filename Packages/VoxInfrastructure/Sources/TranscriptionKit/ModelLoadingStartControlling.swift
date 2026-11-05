import VoxCore
import Foundation

public protocol ModelLoadingStartControlling: AnyObject, Sendable {
    var blocksRecordingUntilModelReady: Bool { get }
}
