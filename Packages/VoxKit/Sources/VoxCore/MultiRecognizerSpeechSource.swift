import Foundation

public protocol MultiRecognizerSpeechSource: SpeechSessionSource {
    var merger: (any TranscriptionMerger)? { get }
}
