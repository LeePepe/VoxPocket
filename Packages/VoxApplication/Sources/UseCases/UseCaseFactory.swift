import Foundation

/// 用例工厂协议
///
/// 提供创建各种用例实例的统一接口，支持依赖注入。
@MainActor
public protocol UseCaseFactory: Sendable {

    /// 创建录音用例
    func makeRecordingUseCase() -> RecordingUseCase

    /// 创建转录用例
    func makeTranscriptionUseCase() -> TranscriptionUseCase

    /// 创建编辑用例
    func makeEditingUseCase() -> EditingUseCase

    /// 创建历史用例
    func makeHistoryUseCase() -> HistoryUseCase

    /// 创建优化用例
    func makeRefinementUseCase() -> RefinementUseCase

    /// 创建会话用例
    func makeSessionUseCase() -> SessionUseCase

    #if os(macOS)
    /// 创建文本注入用例 (macOS)
    func makeTextInjectionUseCase() -> TextInjectionUseCase
    #endif
}

/// 依赖容器协议
///
/// 管理应用级别的依赖注入。
public protocol DependencyContainer: Sendable {

    /// 用例工厂
    var useCaseFactory: UseCaseFactory { get }

    /// 注册依赖
    func register<T>(_ type: T.Type, factory: @escaping @Sendable () -> T)

    /// 解析依赖
    func resolve<T>(_ type: T.Type) -> T?
}
