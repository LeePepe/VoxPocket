import VoxCore
import Combine
import TranscriptionKit

public protocol ModelLoadingObservable: AnyObject, Sendable {
    var modelLoadingState: ModelLoadingState { get }
    var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> { get }
}
