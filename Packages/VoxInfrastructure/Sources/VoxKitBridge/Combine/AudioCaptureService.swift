import VoxCore
import Combine

public protocol AudioCaptureService: AnyObject, Sendable {
    var state: AudioCaptureState { get }
    var statePublisher: AnyPublisher<AudioCaptureState, Never> { get }
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
    func startCapture() async throws
    func stopCapture() async
    func pauseCapture()
    func resumeCapture()
    func requestPermission() async -> Bool
    var hasPermission: Bool { get }
}
