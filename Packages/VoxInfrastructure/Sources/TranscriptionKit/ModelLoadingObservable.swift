import Combine

/// 任何异步加载本地模型的转录器需遵循此协议
/// 供 UI 层订阅加载状态，用于展示进度和阻止录音
public protocol ModelLoadingObservable: AnyObject, Sendable {
    var modelLoadingState: ModelLoadingState { get }
    var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> { get }
}
