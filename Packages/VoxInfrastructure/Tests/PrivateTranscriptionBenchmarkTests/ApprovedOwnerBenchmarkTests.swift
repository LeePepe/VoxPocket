#if os(macOS)
import AVFoundation
import Foundation
import LLMKit
import LokiKit
import XCTest
@testable import TranscriptionKit

enum BenchmarkGroup: String, CaseIterable, Codable, Sendable {
    case appleAutomatic, appleOnDevice, azure, localBase, localTurbo
    case hybridAzure, hybridBase, hybridTurbo
    var usesApple: Bool { self == .appleAutomatic || self == .appleOnDevice || isHybrid }
    var isHybrid: Bool { rawValue.hasPrefix("hybrid") }
    var usesCloud: Bool { self == .azure || isHybrid }
    var localModel: String? {
        switch self {
        case .localBase, .hybridBase: "openai_whisper-base"
        case .localTurbo, .hybridTurbo: "openai_whisper-large-v3_turbo"
        default: nil
        }
    }
}

struct BenchmarkContext: Sendable {
    let root: URL
    let output: URL
    let sourceSHA: String
    let manifest: BenchmarkManifest

    static func load(_ environment: [String: String]) throws -> Self {
        guard let root = environment["VOX_BENCHMARK_ROOT"], let output = environment["VOX_BENCHMARK_OUTPUT"],
              let sha = environment["VOX_BENCHMARK_SHA"], sha.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else {
            throw BenchmarkFailure.invalidConfiguration
        }
        let rootURL = URL(fileURLWithPath: root), outputURL = URL(fileURLWithPath: output)
        let manifest = try ProtectedBenchmarkFiles.manifest(in: rootURL)
        try ProtectedBenchmarkFiles.validateDirectory(outputURL, beneath: rootURL)
        return Self(root: rootURL, output: outputURL, sourceSHA: sha, manifest: manifest)
    }
}

/// 必须显式 opt-in；CI 仅运行合成数据单元测试，不触碰沙箱、权限或模型服务。
final class ApprovedOwnerBenchmarkTests: XCTestCase {
    func testApprovedOwnerRun() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["VOX_BENCHMARK_OPT_IN"] == "approved-owner-sample" else {
            throw XCTSkip("Private benchmark requires explicit owner opt-in")
        }
        do {
            try await Task<Void, Error>.detached { @Sendable [env] in
                let context = try BenchmarkContext.load(env)
                if env["VOX_BENCHMARK_GROUP"] == "prepare" {
                    try BenchmarkPreparation.prepare(context)
                } else if let group = env["VOX_BENCHMARK_GROUP"].flatMap(BenchmarkGroup.init(rawValue:)) {
                    try await BenchmarkExecution(context: context, group: group).run()
                } else { throw BenchmarkFailure.invalidConfiguration }
            }.value
        } catch {
            // 绝不把解码器、路径、供应商错误体或私密字符串传给 XCTest。
            let code = (error as? BenchmarkFailure)?.rawValue ?? "unexpected"
            XCTFail("Benchmark could not produce a protected report: \(code)")
        }
    }

}

enum BenchmarkPreparation {
    static func prepare(_ context: BenchmarkContext) throws {
        let input = context.root.appendingPathComponent(context.manifest.audio_file)
        let validatedInput = try ProtectedBenchmarkFiles.read(input, beneath: context.root, maximumBytes: 25_000_000)
        let start = benchmarkNow()
        let audio = try BenchmarkAudio.decode(validatedInput).canonicalized()
        guard abs(audio.duration - context.manifest.duration_seconds) < 0.1 else {
            throw BenchmarkFailure.invalidAudio
        }
        try ProtectedBenchmarkFiles.writeData(audio.wav(), to: context.output.appendingPathComponent("canonical.wav"),
                                              beneath: context.root)
        try ProtectedBenchmarkFiles.write(["conversion_seconds": benchmarkNow() - start, "audio_seconds": audio.duration],
            to: context.output.appendingPathComponent("preparation.json"), beneath: context.root)
    }
}

struct BenchmarkExecution: Sendable {
    let context: BenchmarkContext
    let group: BenchmarkGroup

    func run() async throws {
        let wav = context.output.appendingPathComponent("canonical.wav")
        let validatedWAV = try ProtectedBenchmarkFiles.read(wav, beneath: context.root, maximumBytes: 2_000_000)
        let audio = try BenchmarkAudio.decode(validatedWAV)
        var runs: [BenchmarkRun] = [], recognized: [String] = [], merged: [String] = [], refined: [String] = []
        let folder = modelFolder()
        let prepareStart = benchmarkNow()
        do {
            let apple = try await group.usesApple ? AppleBenchmarkAdapter(onDevice: group == .appleOnDevice) : nil
            let config = try await group.usesCloud ? BenchmarkCloudConfiguration.load() : nil
            let cloud = config.map { WhisperEngine(config: $0.speech, session: Self.session(), logger: SilentBenchmarkLogger()) }
            let llm = try group.isHybrid ? config.map { try BenchmarkLLMService(config: $0.refinement.providerConfig) } : nil
            let localStart = benchmarkNow()
            let local = try await localEngine(folder)
            let loadSeconds = group.localModel == nil ? nil : benchmarkNow() - localStart
            let preparationSeconds = benchmarkNow() - prepareStart
            for iteration in 0..<6 {
                // 既有云端小配额：仅在运行之间等待，不计入识别耗时。
                if iteration > 0, group == .azure { try await Task.sleep(for: .seconds(15)) }
                let record = await measure(iteration: iteration, audio: audio, wav: validatedWAV, apple: apple,
                                           cloud: cloud, local: local, llm: llm,
                                           loadSeconds: iteration == 0 ? loadSeconds : (local == nil ? nil : 0),
                                           preparationSeconds: iteration == 0 ? preparationSeconds : 0)
                runs.append(record.0); recognized.append(record.1); merged.append(record.2); refined.append(record.3)
            }
        } catch {
            var failed = BenchmarkRun(iteration: 0, cold: true)
            failed.status = (error as? BenchmarkFailure)?.rawValue ?? "preparation_failed"
            failed.preparationSeconds = benchmarkNow() - prepareStart
            runs.append(failed)
        }
        let summary = BenchmarkSummary(provider: group.rawValue, sourceSHA: context.sourceSHA,
            dependencySHA: "eff9c1712cd648ed0717e41183ad8bd7bf39cbea", processID: ProcessInfo.processInfo.processIdentifier,
            generatedAt: Date(), inputPacing: group.usesApple ? "apple_1x_then_batch" : "batch",
            actualAppleRoute: "unknown", cloudBackingModel: "unknown", cachePresent: folder != nil,
            audioSeconds: audio.duration, runs: runs)
        try ProtectedBenchmarkFiles.write(PrivateBenchmarkReport(summary: summary, reference: context.manifest.reference_text,
            recognized: recognized, merged: merged, refined: refined),
            to: context.output.appendingPathComponent("private-\(group.rawValue).json"), beneath: context.root)
        try ProtectedBenchmarkFiles.write(summary, to: context.output.appendingPathComponent("summary-\(group.rawValue).json"),
                                           beneath: context.root)
    }

    private func measure(iteration: Int, audio: BenchmarkAudio, wav: Data, apple: AppleBenchmarkAdapter?,
                         cloud: WhisperEngine?, local: LocalWhisperKitEngine?, llm: BenchmarkLLMService?,
                         loadSeconds: Double?, preparationSeconds: Double) async -> (BenchmarkRun, String, String, String) {
        var run = BenchmarkRun(iteration: iteration, cold: iteration == 0)
        run.loadSeconds = loadSeconds
        run.preparationSeconds = preparationSeconds
        let start = benchmarkNow()
        var text = "", mergeText = "", refinedText = ""
        do {
            let appleResult = try await apple?.recognize(audio)
            run.firstPartialSeconds = appleResult?.firstPartial
            run.inputSeconds = appleResult?.inputSeconds
            let asrStart = benchmarkNow()
            if let local { text = try await local.transcribeCanonicalSamples(audio.samples, languageCode: "zh") ?? "" }
            else if group == .azure || group == .hybridAzure, let cloud {
                text = try await cloud.transcribe(audioData: wav, language: Locale(identifier: "zh-Hans"))
            } else { text = appleResult?.text ?? "" }
            guard !text.isEmpty else { throw BenchmarkFailure.emptyResult }
            run.requestSeconds = appleResult != nil && !group.isHybrid ? appleResult?.totalSeconds : benchmarkNow() - asrStart
            run.score = BenchmarkScoring.score(reference: context.manifest.reference_text, recognized: text)
            run.asrScore = run.score
            if let appleResult, let llm {
                let before = benchmarkNow()
                llm.reset()
                mergeText = await mergedTranscription(appleSpeech: appleResult.text, whisper: text,
                    merger: LLMTranscriptionMerger(llmService: llm, logger: SilentBenchmarkLogger()))
                run.mergeSeconds = benchmarkNow() - before
                run.mergedScore = BenchmarkScoring.score(reference: context.manifest.reference_text, recognized: mergeText)
                run.mergeDisposition = appleResult.text == text || appleResult.text.isEmpty ? "skipped" :
                    llm.disposition(maxLength: max(text.count, appleResult.text.count))
                let refinementStart = benchmarkNow()
                refinedText = try await llm.refine(RefinementRequest(text: mergeText)).refinedText
                run.refinementSeconds = benchmarkNow() - refinementStart
                run.score = BenchmarkScoring.score(reference: context.manifest.reference_text, recognized: refinedText)
            }
        } catch { run.status = (error as? BenchmarkFailure)?.rawValue ?? "provider_failed" }
        run.totalSeconds = benchmarkNow() - start
        run.realTimeFactor = (run.totalSeconds ?? 0) / audio.duration
        if let input = run.inputSeconds { run.finalAfterInputSeconds = max(0, (run.totalSeconds ?? 0) - input) }
        return (run, text, mergeText, refinedText)
    }

    private func localEngine(_ folder: URL?) async throws -> LocalWhisperKitEngine? {
        guard let model = group.localModel else { return nil }
        guard let folder else { throw BenchmarkFailure.missingModel }
        let engine = LocalWhisperKitEngine(config: LocalWhisperKitConfig(model: model, preloadOnStart: false),
                                          logger: SilentBenchmarkLogger(), preparedModelFolder: folder)
        try await engine.prepare(onProgress: nil)
        return engine
    }

    private func modelFolder() -> URL? {
        guard let model = group.localModel else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let relative = "VoxPocketWhisperKitHub/models/argmaxinc/whisperkit-coreml/\(model)"
        let roots = [home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Containers/com.leepepe.voxpocket/Data/Library/Caches")]
        return roots.map { $0.appendingPathComponent(relative) }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("TextDecoder.mlmodelc").path)
        }
    }

    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        config.urlCache = nil
        return URLSession(configuration: config)
    }
}
#endif
