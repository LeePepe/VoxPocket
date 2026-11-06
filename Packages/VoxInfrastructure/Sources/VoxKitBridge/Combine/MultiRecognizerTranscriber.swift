import VoxCore

public protocol MultiRecognizerTranscriber: TranscriptionCoordinator {
    var merger: (any TranscriptionMerger)? { get }
}
