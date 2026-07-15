import Foundation
import Combine
import TranscriptionKit

/// 本地模型加载状态的 ObservableObject 包装
///
/// 供 SwiftUI 视图订阅 ModelLoadingObservable 的状态变化。
@MainActor
public final class LocalModelLoadingStatus: ObservableObject {

    @Published public private(set) var state: ModelLoadingState

    private var cancellable: AnyCancellable?

    public init(observable: any ModelLoadingObservable) {
        self.state = observable.modelLoadingState
        cancellable = observable.modelLoadingStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
            }
    }

    /// 当前是否正在下载或初始化
    public var isInProgress: Bool {
        state.isInProgress
    }

    /// 人类可读的状态描述
    public var statusText: String {
        switch state {
        case .idle:
            return "未启动"
        case .downloading(let progress):
            return "正在下载模型… \(Int(progress * 100))%"
        case .loading:
            return "正在初始化模型…"
        case .ready:
            return "模型已就绪"
        case .failed(let reason):
            return "加载失败：\(reason)"
        }
    }

    /// 下载进度（仅在 .downloading 时有值）
    public var downloadProgress: Double? {
        if case .downloading(let p) = state { return p }
        return nil
    }
}
