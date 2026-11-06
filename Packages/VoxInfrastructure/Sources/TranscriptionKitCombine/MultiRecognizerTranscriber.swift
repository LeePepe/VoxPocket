import VoxCore
import TranscriptionKit

public protocol MultiRecognizerTranscriber: TranscriptionCoordinator {
    var merger: (any TranscriptionMerger)? { get }
}
