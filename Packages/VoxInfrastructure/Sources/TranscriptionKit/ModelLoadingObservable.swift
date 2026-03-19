import Combine

/// 任何异步加载本地模型的转录器需遵循此协议
/// 供 UI 层订阅加载状态，用于展示进度和阻止录音
public protocol ModelLoadingObservable: AnyObject, Sendable {
    var modelLoadingState: ModelLoadingState { get }
    var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> { get }
}

/// 控制模型加载状态是否应阻止开始录音。
public protocol ModelLoadingStartControlling: AnyObject, Sendable {
    /// `true` 表示模型未 ready 时应阻止开始录音；
    /// `false` 表示可以先开始录音，待模型就绪后再补充后处理。
    var blocksRecordingUntilModelReady: Bool { get }
}
