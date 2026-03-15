import Foundation

/// 支持按需启动本地模型预加载。
public protocol ModelPreloadControlling: AnyObject, Sendable {
    /// 若模型尚未开始加载，则启动后台预加载；已在加载或已就绪时应无副作用。
    func startModelPreloadIfNeeded()
}
