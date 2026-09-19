import Foundation
import Synchronization
import Preferences
import LLMKit

struct StageTextModelServices {
    let main: DefaultStageTextModelService
    let quick: DefaultStageTextModelService
    init(azureConfig: LLMProviderConfig?, settings: StageModelSettings) {
        main = DefaultStageTextModelService(azureFoundryConfig: azureConfig, settings: settings)
        quick = DefaultStageTextModelService(azureFoundryConfig: azureConfig, settings: settings)
    }
}

/// 每个录音入口独占一个服务槽；新录音创建新配置，不修改正在精炼的实例。
/// 文本配置失败只影响文本请求，不能阻止语音采集，也不能偷偷改用另一模型。
public final class DefaultStageTextModelService: LLMService, Sendable {
    public enum ConfigurationError: Error, LocalizedError {
        case unavailable
        public var errorDescription: String? { "所选文本模型尚未配置，请检查语音与文本设置。" }
    }
    private let azureConfig: LLMProviderConfig?
    private let selection: Mutex<Result<DefaultLLMService, ConfigurationError>>

    public init(azureFoundryConfig: LLMProviderConfig?, settings: StageModelSettings) {
        azureConfig = azureFoundryConfig
        selection = Mutex(Self.makeService(config: azureFoundryConfig, settings: settings))
    }

    public func configure(_ settings: StageModelSettings) {
        let next = Self.makeService(config: azureConfig, settings: settings)
        selection.withLock { $0 = next }
    }

    private static func makeService(config: LLMProviderConfig?, settings: StageModelSettings)
        -> Result<DefaultLLMService, ConfigurationError> {
        let service = DefaultLLMService(azureFoundryConfig: config)
        do {
            try StageModelRouting.applyTextModels(settings, to: service)
            if settings.refinement == .azureFoundry, service.currentProvider?.isAvailable != true {
                return .failure(.unavailable)
            }
            return .success(service)
        } catch { return .failure(.unavailable) }
    }

    private func snapshot() throws -> DefaultLLMService { try selection.withLock { $0 }.get() }
    public var availableProviders: [LLMProviderType] { (try? snapshot().availableProviders) ?? [] }
    public var currentProvider: (any LLMProvider)? { try? snapshot().currentProvider }
    public var currentProviderType: LLMProviderType? { try? snapshot().currentProviderType }
    public func setProvider(_ config: LLMProviderConfig) throws { try snapshot().setProvider(config) }
    public func setSkipContentAnalysis(_ skip: Bool) { try? snapshot().setSkipContentAnalysis(skip) }
    public func complete(prompt: String) async throws -> String { try await snapshot().complete(prompt: prompt) }
    public func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        try await snapshot().completeStreaming(prompt: prompt)
    }
    public func refine(_ request: RefinementRequest) async throws -> RefinementResponse { try await snapshot().refine(request) }
    public func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        try await snapshot().refineStreaming(request)
    }
    public func cancel() { try? snapshot().cancel() }
    public func validateCurrentProvider() async -> Bool {
        guard let service = try? snapshot() else { return false }
        return await service.validateCurrentProvider()
    }
}
