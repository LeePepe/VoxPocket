import Foundation
import Synchronization
import VoxCore
#if canImport(WhisperKit)
import WhisperKit
#endif

// MARK: - Engine abstraction

protocol LocalWhisperEngine: Sendable {
    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws
    func startStreaming(

        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws
    func stopStreaming() async
    func pauseStreaming() async
    func resumeStreaming() async
    /// 停止后对全量音频做一次完整转录，捕捉最后 <1s 的未解码内容
    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String?
    /// 对指定音频文件做完整转录（供 Hybrid 模式使用）
    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String?
}

private actor SharedLocalWhisperEnginePool {
    static let shared = SharedLocalWhisperEnginePool()

    private var engines: [String: any LocalWhisperEngine] = [:]

    func engine(for config: LocalWhisperKitConfig, logger: any VoxLogger, storageLocations: VoxStorageLocations) -> any LocalWhisperEngine {
        let key = config.resolvedModelVariant + storageLocations.modelCache.absoluteString
        if let existing = engines[key] {
            return existing
        }

        let engine = LocalWhisperKitEngine(config: config, logger: logger, storageLocations: storageLocations)
        engines[key] = engine
        return engine
    }
}

final class SharedLocalWhisperEngineHandle: LocalWhisperEngine {
    private let config: LocalWhisperKitConfig
    private let logger: any VoxLogger
    private let storageLocations: VoxStorageLocations

    init(config: LocalWhisperKitConfig, logger: any VoxLogger, storageLocations: VoxStorageLocations) {
        self.storageLocations = storageLocations
        self.config = config
        self.logger = logger
    }

    private func engine() async -> any LocalWhisperEngine {
        await SharedLocalWhisperEnginePool.shared.engine(for: config, logger: logger, storageLocations: storageLocations)
    }

    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        let engine = await engine()
        try await engine.prepare(onProgress: onProgress)
    }

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        let engine = await engine()
        try await engine.startStreaming(
            languageCode: languageCode,
            onPartial: onPartial,
            onAudioLevel: onAudioLevel
        )
    }

    func stopStreaming() async {
        let engine = await engine()
        await engine.stopStreaming()
    }

    func pauseStreaming() async {
        let engine = await engine()
        await engine.pauseStreaming()
    }

    func resumeStreaming() async {
        let engine = await engine()
        await engine.resumeStreaming()
    }

    func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? {
        let engine = await engine()
        return try await engine.transcribeAccumulatedAudio(languageCode: languageCode)
    }

    func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? {
        let engine = await engine()
        return try await engine.transcribeAudioFile(atPath: path, languageCode: languageCode)
    }
}

actor LocalWhisperKitEngine: LocalWhisperEngine {
    private let config: LocalWhisperKitConfig
    private let logger: any VoxLogger
    private let storageLocations: VoxStorageLocations
    /// 仅供独立文件评测：绕过共享池、下载与缓存修复；生产入口保持原行为。
    private let preparedModelFolder: URL?

#if canImport(WhisperKit)
    private let pipelineStorage = Mutex<WhisperKit?>(nil)
    // 评测引擎独占借出；异步调用期间池中为空，杜绝可重入访问非 Sendable 的供应商对象。
    private let benchmarkPipeline = Mutex<WhisperKit?>(nil)
    private var benchmarkPrepared = false
    private let streamControl = WhisperStreamControl()
    private var streamTask: Task<Void, Error>?
    private var prepareTask: Task<Void, Error>?
#endif

    init(config: LocalWhisperKitConfig, logger: any VoxLogger, preparedModelFolder: URL? = nil, storageLocations: VoxStorageLocations) {
        self.storageLocations = storageLocations
        self.config = config
        self.logger = logger
        self.preparedModelFolder = preparedModelFolder
    }

    private static func isRecoverableSnapshotError(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains(".incomplete")
            || text.contains("couldn’t be moved")
            || text.contains("couldn't be moved")
    }

    func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
#if canImport(WhisperKit)
        if pipelineStorage.withLock({ $0 != nil }) || benchmarkPrepared {
            return
        }

        if let prepareTask {
            try await prepareTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            try await self.performPrepare(onProgress: onProgress)
        }
        prepareTask = task
        defer { prepareTask = nil }

        try await task.value
#else
        _ = onProgress
        throw NSError(
            domain: "WhisperKitTranscriber", code: -100,
            userInfo: [NSLocalizedDescriptionKey: "WhisperKit module unavailable in current build"]
        )
#endif
    }

#if canImport(WhisperKit)
    private func performPrepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
        if let preparedModelFolder {
            try await loadBenchmarkPipeline(from: preparedModelFolder)
            benchmarkPrepared = true
            return
        }
        let modelVariant = config.resolvedModelVariant
        logger.info("Downloading/locating WhisperKit model", fields: [.label("model", .source("whisperKit"))])
        if modelVariant != config.model {
            logger.info("Resolved WhisperKit variant", fields: [.label("model", .source("whisperKit"))])
        }
        let cache = WhisperKitModelCacheAdapter(storageLocations: storageLocations)
        let downloadBase = try cache.prepareDirectory()

        let downloadModel: () async throws -> URL = { [logger = self.logger] in
            try await WhisperKit.download(
                variant: modelVariant,
                downloadBase: downloadBase,
                progressCallback: { progress in
                    let pct = Int(progress.fractionCompleted * 100)
                    let completed = progress.completedUnitCount
                    let total = progress.totalUnitCount
                    if total > 0 {
                        logger.info("WhisperKit model download", fields: [.int("percent", pct), .int("completed", Int(completed)), .int("total", Int(total))])
                    } else {
                        logger.info("WhisperKit model download", fields: [.int("percent", pct)])
                    }
                    onProgress?(progress.fractionCompleted)
                }
            )
        }

        var lastModelFolder: URL?
        let initializePipeline: () async throws -> WhisperKit = { [self] in
            let modelFolder = try await downloadModel()
            lastModelFolder = modelFolder
            self.logger.info("Model ready")
            onProgress?(1.0)

            self.logger.info("Loading WhisperKit pipeline from model folder...")
            let whisperConfig = WhisperKitConfig(modelFolder: modelFolder.path)
            return try await WhisperKit(whisperConfig)
        }

        do {
            let loaded = try await initializePipeline()
            returnPipeline(loaded)
        } catch {
            guard Self.isRecoverableSnapshotError(error) else { throw error }
            logger.warning("WhisperKit cache appears corrupted. Clearing cache and retrying once.")
            try cache.reset(modelFolder: lastModelFolder)
            let loaded = try await initializePipeline()
            returnPipeline(loaded)
        }
        logger.info("WhisperKit pipeline loaded successfully")
    }
#endif

#if canImport(WhisperKit)
    private nonisolated func takePipeline() -> sending WhisperKit? {
        pipelineStorage.withLock { state in
            let pipeline = state
            state = nil
            return pipeline
        }
    }

    private nonisolated func returnPipeline(_ pipeline: sending WhisperKit) {
        let transfer = Mutex<WhisperKit?>(pipeline)
        pipelineStorage.withLock { destination in
            destination = transfer.withLock { source in
                let pipeline = source
                source = nil
                return pipeline
            }
        }
    }

#endif

    func startStreaming(
        languageCode: String?,
        onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
#if canImport(WhisperKit)
        guard streamTask == nil else { return }
        try await prepare(onProgress: nil)
        guard let pipeline = takePipeline() else { throw VoxKitError.modelNotReady }
        streamControl.state.withLock { $0 = WhisperStreamControl.State() }
        let owner = WhisperStreamingOwner(pipeline: pipeline)
        do {
            try await owner.start(languageCode: languageCode, control: streamControl,
                                  onPartial: onPartial, onAudioLevel: onAudioLevel)
        } catch {
            if let returned = await owner.recover() { returnPipeline(returned) }
            throw error
        }
        streamTask = Task { [self] in
            do {
                let returned = try await owner.run()
                returnPipeline(returned)
            } catch {
                let returned = await owner.recover()
                if let returned { returnPipeline(returned) }
                throw error
            }
        }
#else
        throw VoxKitError.speechRecognitionUnavailable
#endif
    }

    func stopStreaming() async {
#if canImport(WhisperKit)
        streamControl.state.withLock { $0.stopped = true }
        if let task = streamTask { _ = await task.result }
        streamTask = nil
#endif
    }

    nonisolated func transcribeAccumulatedAudio(languageCode: String?) async throws -> String? {
#if canImport(WhisperKit)
        guard let pipeline = takePipeline() else { return nil }
        let allSamples = Array(pipeline.audioProcessor.audioSamples)
        guard !allSamples.isEmpty else { returnPipeline(pipeline); return nil }

        var options = DecodingOptions()
        options.language = languageCode
        // 限制 temperature fallback 次数（默认 5 次 → 2 次），减少短录音批量解码卡顿
        options.temperatureFallbackCount = 2
        // 放宽 firstTokenLogProbThreshold 避免在低质量音频上触发过多重试
        options.firstTokenLogProbThreshold = -2.5
        // 批量解码不需要 prefill，跳过可加快速度
        options.usePrefillPrompt = false
        options.usePrefillCache = false

        do {
            let results = try await pipeline.transcribe(audioArray: allSamples, decodeOptions: options)
            let text = results
                .compactMap { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            returnPipeline(pipeline)
            return text.isEmpty ? nil : text
        } catch {
            returnPipeline(pipeline)
            throw error
        }
#else
        _ = languageCode
        return nil
#endif
    }

    nonisolated func transcribeAudioFile(atPath path: String, languageCode: String?) async throws -> String? {
#if canImport(WhisperKit)
        guard let pipeline = takePipeline() else { return nil }

        var options = DecodingOptions()
        options.language = languageCode

        do {
            let results = try await pipeline.transcribe(audioPath: path, decodeOptions: options)
            let text = results
                .compactMap { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            returnPipeline(pipeline)
            return text.isEmpty ? nil : text
        } catch {
            returnPipeline(pipeline)
            throw error
        }
#else
        _ = path
        _ = languageCode
        return nil
#endif
    }

    /// 与文件模式相同的解码选项，直接消费已规范化、已校验的 16kHz 单声道样本。
    nonisolated func transcribeCanonicalSamples(_ samples: [Float], languageCode: String?) async throws -> String? {
#if canImport(WhisperKit)
        let checkedOut = benchmarkPipeline.withLock { state in
            let value = state
            state = nil
            return value
        }
        guard let checkedOut else { return nil }
        var options = DecodingOptions()
        options.language = languageCode
        do {
            let results = try await checkedOut.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            returnBenchmarkPipeline(checkedOut)
            return text.isEmpty ? nil : text
        } catch {
            returnBenchmarkPipeline(checkedOut)
            throw error
        }
#else
        return nil
#endif
    }

#if canImport(WhisperKit)
    private nonisolated func loadBenchmarkPipeline(from folder: URL) async throws {
        let loaded = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, download: false))
        returnBenchmarkPipeline(loaded)
    }

    private nonisolated func returnBenchmarkPipeline(_ pipeline: sending WhisperKit) {
        // sending 转移所有权；中转 Mutex 使闭包不捕获仍属于调用方隔离域的引用。
        let transfer = Mutex<WhisperKit?>(pipeline)
        benchmarkPipeline.withLock { destination in
            destination = transfer.withLock { source in
                let value = source
                source = nil
                return value
            }
        }
    }
#endif

    func pauseStreaming() async {
#if canImport(WhisperKit)
        streamControl.state.withLock { $0.paused = true }
#endif
    }

    func resumeStreaming() async {
#if canImport(WhisperKit)
        streamControl.state.withLock { $0.paused = false }
#endif
    }


}

#if canImport(WhisperKit)
extension WhisperKit {
    func tokenizerRequired() throws -> any WhisperTokenizer {
        if let tokenizer {
            return tokenizer
        }
        throw NSError(
            domain: "WhisperKitTranscriber", code: -103,
            userInfo: [NSLocalizedDescriptionKey: "WhisperKit tokenizer unavailable"]
        )
    }
}
#endif
