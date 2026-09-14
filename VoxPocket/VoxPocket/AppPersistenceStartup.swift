import Foundation

/// 存储启动不依赖窗口生命周期；并发入口共享同一任务，避免重复打开数据库或切换代理。
@MainActor
final class AppPersistenceStartup {
    private var preparation: Task<Bool, Never>?

    func prepare(_ load: @escaping @MainActor () async throws -> Void) async -> Bool {
        if let preparation { return await preparation.value }
        let task = Task { @MainActor in
            do {
                try await load()
                return true
            } catch {
                // 调用方记录固定诊断；不传播可能包含用户路径/内容的错误正文。
                return false
            }
        }
        preparation = task
        return await task.value
    }
}
