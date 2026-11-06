import Foundation

public enum TranscriptionEvent: Sendable, Equatable {
    case partial(TranscriptionResult)
    case final(TranscriptionResult)
    case level(Float)
    case state(AudioCaptureState)
}

public protocol SpeechSession: Sendable {
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error>
    func pause() async
    func resume() async
    func stop() async
    func cancel() async
}
