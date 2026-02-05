import Foundation

/// 录音器状态
public enum RecorderStatus: String, CaseIterable {
    case idle = "Idle"
    case listening = "Listening"
    case transcribing = "Transcribing"
    case refining = "Refining"
    case done = "Done"
    case error = "Error"
}
