import VoxCore
import Foundation

public protocol ModelLoadingStateProviding: AnyObject, Sendable {
    var modelLoadingState: ModelLoadingState { get }
    func modelLoadingStates() -> AsyncStream<ModelLoadingState>
}
