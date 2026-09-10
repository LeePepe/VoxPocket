import Combine
import Foundation
import OSLog

/// 正常启动系统事件循环，再异步加载配置；所有服务入口共享同一道门。
@MainActor
final class AppStartup: ObservableObject {
    enum Phase: Equatable { case loading, ready, failed }

    static let shared = AppStartup(loadConfiguration: LLMAppConfig.loadRuntimeConfiguration)

    @Published private(set) var phase: Phase = .loading
    private let loadConfiguration: @MainActor () async throws -> Void
    private var preparation: Task<Bool, Never>?

    init(loadConfiguration: @escaping @MainActor () async throws -> Void) {
        self.loadConfiguration = loadConfiguration
    }

    /// 窗口关闭只取消调用者；配置加载不随单个视图任务取消，也不重复读取。
    func prepare() async -> Bool {
        if let preparation { return await preparation.value }
        let task = Task { @MainActor in
            do {
                try await loadConfiguration()
                phase = .ready
                Logger(subsystem: "com.leepepe.voxpocket", category: "AppStartup")
                    .info("Configuration ready; app services may start")
                return true
            } catch {
                phase = .failed
                // 不记录任意错误正文；错误配置不创建服务、不静默回退。
                Logger(subsystem: "com.leepepe.voxpocket", category: "AppStartup")
                    .error("Model configuration could not be loaded; app services remain disabled")
                return false
            }
        }
        preparation = task
        return await task.value
    }
}
