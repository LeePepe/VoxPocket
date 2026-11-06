import VoxCore
import Combine
import Foundation
import TranscriptionKit

public protocol TranscriptionCoordinator: AnyObject, Sendable {
    var audioCaptureService: any AudioCaptureService { get }
    var speechRecognitionService: any SpeechRecognitionService { get }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { get }
    var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> { get }
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
    var isTranscribing: Bool { get }
    func start(language: Locale) async throws
    func stop() async
    func pause()
    func resume()
}
