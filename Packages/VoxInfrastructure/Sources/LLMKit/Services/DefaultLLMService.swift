import Foundation
import Combine
import CoreModels
import Synchronization
import Observability
import AsyncAlgorithms

/// LLM 服务默认实现
///
/// 管理多个 LLM 提供者，代理请求到当前活跃的提供者。
/// 初始化时自动注册 Apple Intelligence 提供者（如果设备支持）。
public final class DefaultLLMService: LLMService, Sendable {

    private struct State: Sendable {
        var providers: [LLMProviderType: any LLMProvider] = [:]
        var currentProvider: (any LLMProvider)?
        var analysisProviderOverrides: [AnalysisStep: LLMProviderType] = [:]
    }

    private let state: Mutex<State>
    private let logger: Logger

    public init(logger: Logger? = nil) {
        self.logger = logger ?? PrintLogger(subsystem: "LLMService", minimumLevel: .debug)
        let aiProvider = AppleIntelligenceProvider(logger: self.logger)
        let initialState = State(
            providers: [.appleIntelligence: aiProvider],
            currentProvider: aiProvider
        )
        self.state = Mutex(initialState)
    }

    // MARK: - Streaming Helpers

    private func streamFromSingle(
        _ operation: @escaping @Sendable () async throws -> String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    let value = try await operation()
                    continuation.yield(value)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func collectToString(
        from stream: AsyncThrowingStream<String, Error>
    ) async throws -> String {
        let chunks = try await Array(stream)
        return chunks.joined()
    }

    // MARK: - LLMService

    public var availableProviders: [LLMProviderType] {
        state.withLock { Array($0.providers.keys) }
    }

    public var currentProvider: (any LLMProvider)? {
        state.withLock { $0.currentProvider }
    }

    public var currentProviderType: LLMProviderType? {
        state.withLock { $0.currentProvider?.providerType }
    }

    public func setProvider(_ config: LLMProviderConfig) throws {
        try state.withLock { state in
            guard let provider = state.providers[config.providerType] else {
                throw VoxError.llmProviderNotConfigured
            }
            state.currentProvider = provider
            state.analysisProviderOverrides = Self.analysisProviderOverrides(from: config.options)
        }
    }

    // MARK: - Analysis

    private static func analysisProviderOverrides(
        from options: [String: String]
    ) -> [AnalysisStep: LLMProviderType] {
        let mapping: [(AnalysisStep, String)] = [
            (.intent, "analysis.intent.provider"),
            (.tone, "analysis.tone.provider"),
            (.entities, "analysis.entities.provider"),
            (.tags, "analysis.tags.provider"),
            (.params, "analysis.params.provider"),
        ]

        var result: [AnalysisStep: LLMProviderType] = [:]
        for (step, key) in mapping {
            guard let rawValue = options[key],
                  let providerType = LLMProviderType(rawValue: rawValue) else {
                continue
            }
            result[step] = providerType
        }
        return result
    }

    private typealias AnalysisResult = (
        intent: IntentAnalysis,
        tone: ToneAnalysis,
        missingSteps: Set<AnalysisStep>
    )

    private func analyzeContent(_ request: RefinementRequest) async -> AnalysisResult {
        let snapshot = state.withLock { state in
            (
                providers: state.providers,
                currentProviderType: state.currentProvider?.providerType,
                overrides: state.analysisProviderOverrides
            )
        }

        guard let defaultProviderType = snapshot.currentProviderType else {
            logger.log(.error, "分析失败：未配置默认 provider", context: [
                "text_length": request.text.count
            ], file: #file, function: #function, line: #line)
            return (IntentAnalysis(), ToneAnalysis(), Set(AnalysisStep.allCases))
        }

        var providersByStep: [AnalysisStep: LLMProviderType] = [:]
        for step in AnalysisStep.allCases {
            providersByStep[step] = snapshot.overrides[step] ?? defaultProviderType
        }

        var stepsByProvider: [LLMProviderType: Set<AnalysisStep>] = [:]
        for (step, providerType) in providersByStep {
            stepsByProvider[providerType, default: []].insert(step)
        }

        var intent = IntentAnalysis()
        var tone = ToneAnalysis()
        var entities: [String] = []
        var tags: [String] = []
        var params = IntentParams()
        var missing = Set(AnalysisStep.allCases)

        logger.log(.info, "开始内容分析", context: [
            "text_length": request.text.count,
            "default_provider": defaultProviderType.rawValue,
            "providers_by_step": providersByStep
                .map { "\($0.key.rawValue):\($0.value.rawValue)" }
                .sorted()
                .joined(separator: ", ")
        ], file: #file, function: #function, line: #line)

        let analysisRequest = AnalysisRequest(
            text: request.text,
            options: request.options,
            transcriptionMetadata: request.transcriptionMetadata
        )

        for (providerType, steps) in stepsByProvider {
            guard let provider = snapshot.providers[providerType] else {
                missing.formUnion(steps)
                logger.log(.error, "分析 provider 缺失，使用默认值", context: [
                    "provider": providerType.rawValue,
                    "steps": steps.map { $0.rawValue }.joined(separator: ", ")
                ], file: #file, function: #function, line: #line)
                continue
            }

            let intentSteps = steps.intersection([.intent, .entities, .tags, .params])
            let toneSteps = steps.intersection([.tone])

            func handleSteps(_ stepSet: Set<AnalysisStep>) async {
                guard !stepSet.isEmpty else { return }
                let stepLabel = stepSet.map { $0.rawValue }.sorted().joined(separator: ", ")
                logger.log(.info, "开始分析步骤", context: [
                    "provider": providerType.rawValue,
                    "steps": stepLabel
                ], file: #file, function: #function, line: #line)

                let perfStart = logger.performanceStart()
                do {
                    let partial = try await provider.analyze(analysisRequest, steps: stepSet)

                    // 记录详细的分析结果
                    var resultContext: [String: Any] = [
                        "provider": providerType.rawValue,
                        "steps": stepLabel
                    ]

                    if stepSet.contains(.intent), let value = partial.intent {
                        intent = value
                        missing.remove(.intent)
                        resultContext["intent"] = value.intent.rawValue
                        resultContext["intent_confidence"] = value.confidence
                    }
                    if stepSet.contains(.tone), let value = partial.tone {
                        tone = value
                        missing.remove(.tone)
                        resultContext["tone"] = value.tone.rawValue
                        resultContext["tone_confidence"] = value.confidence
                    }
                    if stepSet.contains(.entities), let value = partial.entities {
                        entities = value
                        missing.remove(.entities)
                        resultContext["entities_count"] = value.count
                        resultContext["entities"] = value.joined(separator: ", ")
                    }
                    if stepSet.contains(.tags), let value = partial.tags {
                        tags = value
                        missing.remove(.tags)
                        resultContext["tags_count"] = value.count
                        resultContext["tags"] = value.joined(separator: ", ")
                    }
                    if stepSet.contains(.params), let value = partial.params {
                        params = value
                        missing.remove(.params)
                        if let targetLang = value.targetLanguage {
                            resultContext["target_language"] = targetLang
                        }
                    }

                    logger.performanceEnd(
                        "分析步骤",
                        start: perfStart,
                        context: resultContext,
                        file: #file,
                        function: #function,
                        line: #line
                    )
                } catch {
                    logger.performanceEnd(
                        "分析步骤",
                        start: perfStart,
                        context: [
                            "provider": providerType.rawValue,
                            "steps": stepLabel
                        ],
                        error: error,
                        file: #file,
                        function: #function,
                        line: #line
                    )
                    missing.formUnion(stepSet)
                    logger.log(.warning, "分析步骤失败，使用默认值", context: [
                        "provider": providerType.rawValue,
                        "steps": stepLabel
                    ], file: #file, function: #function, line: #line)
                }
            }

            // 顺序执行 intent 和 tone 步骤
            // 注意：虽然并行执行可以提高性能，但由于 handleSteps 修改共享状态，
            // Swift 严格并发检查会报错。实际的并行优化在 AppleIntelligenceProvider 中实现。
            await handleSteps(intentSteps)
            await handleSteps(toneSteps)
        }

        let finalIntent = IntentAnalysis(
            intent: intent.intent,
            confidence: intent.confidence,
            params: params,
            entities: entities,
            tags: tags
        )

        let analysis = (intent: finalIntent, tone: tone, missingSteps: missing)
        logger.log(.info, "内容分析完成", context: [
            "missing_steps": missing.map { $0.rawValue }.sorted().joined(separator: ", "),
            "intent": analysis.intent.intent.rawValue,
            "tone": analysis.tone.tone.rawValue,
            "entities_count": finalIntent.entities.count,
            "tags_count": finalIntent.tags.count
        ], file: #file, function: #function, line: #line)
        return analysis
    }

    // MARK: - 通用文本完成

    public func complete(prompt: String) async throws -> String {
        let stream = try await completeStreaming(prompt: prompt)
        return try await collectToString(from: stream)
    }

    public func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let provider = currentProvider else {
            throw VoxError.llmProviderNotConfigured
        }
        return try await provider.completeStreaming(prompt: prompt)
    }

    // MARK: - 文本优化（便捷方法）

    public func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        guard let provider = currentProvider else {
            throw VoxError.llmProviderNotConfigured
        }

        logger.log(.info, "开始文本优化", context: [
            "text_length": request.text.count,
            "provider": provider.providerType.rawValue
        ], file: #file, function: #function, line: #line)
        let analysis = await analyzeContent(request)
        let prompt = RefinementPromptBuilder.build(
            text: request.text,
            customPrompt: request.customPrompt
        )
        let refinedText = try await provider.complete(prompt: prompt)
        logger.log(.info, "文本优化完成", context: [
            "original_length": request.text.count,
            "refined_length": refinedText.count,
            "provider": provider.providerType.rawValue
        ], file: #file, function: #function, line: #line)
        return RefinementResponse(
            originalText: request.text,
            refinedText: refinedText,
            intentAnalysis: analysis.intent,
            toneAnalysis: analysis.tone,
            missingAnalysisSteps: analysis.missingSteps
        )
    }

    public func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        guard let provider = currentProvider else {
            throw VoxError.llmProviderNotConfigured
        }
        logger.log(.info, "开始流式文本优化（跳过分析以提高性能）", context: [
            "text_length": request.text.count,
            "provider": provider.providerType.rawValue
        ], file: #file, function: #function, line: #line)

        // FIXME: 暂时禁用意图/语气分析，因为 Apple Intelligence 的 guided generation
        // 存在严重性能问题（超时 120+ 秒）。直接进行文本优化。
        // _ = await analyzeContent(request)

        let prompt = RefinementPromptBuilder.build(
            text: request.text,
            customPrompt: request.customPrompt
        )
        let stream = try await completeStreaming(prompt: prompt)
        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    logger.log(.info, "流式文本优化完成", context: [
                        "provider": provider.providerType.rawValue
                    ], file: #file, function: #function, line: #line)
                    continuation.finish()
                } catch {
                    logger.log(.error, "流式文本优化失败", context: [
                        "provider": provider.providerType.rawValue,
                        "error": error.localizedDescription
                    ], file: #file, function: #function, line: #line)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancel() {
        currentProvider?.cancel()
    }

    public func validateCurrentProvider() async -> Bool {
        guard let provider = currentProvider else {
            return false
        }
        do {
            try await provider.validate()
            return true
        } catch {
            return false
        }
    }
}
