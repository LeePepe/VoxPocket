import VoxCore
import Foundation

public enum AudioCaptureState: Sendable, Equatable {
    case idle
    case recording
    case paused
    case interrupted
    case error(String)
}
