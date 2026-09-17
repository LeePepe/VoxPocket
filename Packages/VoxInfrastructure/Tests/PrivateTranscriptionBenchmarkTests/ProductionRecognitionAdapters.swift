#if os(macOS)
import AVFoundation
import Foundation
import LLMKit
import LokiKit
import Preferences
import Speech
import Synchronization
@testable import TranscriptionKit

struct AppleBenchmarkResult: Sendable {
    let text: String
    let firstPartial: Double?
    let inputSeconds: Double
    let totalSeconds: Double
}

@MainActor
final class AppleBenchmarkAdapter {
    private let recognizer: SFSpeechRecognizer
    private let onDevice: Bool

    init(onDevice: Bool) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw BenchmarkFailure.unauthorized }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans")),
              recognizer.isAvailable, !onDevice || recognizer.supportsOnDeviceRecognition else {
            throw BenchmarkFailure.unavailable
        }
        self.recognizer = recognizer
        self.onDevice = onDevice
    }

    func recognize(_ audio: BenchmarkAudio) async throws -> AppleBenchmarkResult {
        let request = DefaultAppleSpeechRequestFactory.makeRequest()
        request.requiresOnDeviceRecognition = onDevice
        let started = benchmarkNow()
        let (stream, continuation) = AsyncThrowingStream<(String, Bool, Double), Error>.makeStream()
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                continuation.yield((result.bestTranscription.formattedString, result.isFinal, benchmarkNow()))
                if result.isFinal { continuation.finish() }
            } else if error != nil { continuation.finish(throwing: BenchmarkFailure.recognitionFailed) }
        }
        var inputEnd: Double?
        let feeder = Task { @MainActor in
            do {
                try await Self.feed(audio, to: request, started: started)
                inputEnd = benchmarkNow()
                request.endAudio()
            } catch { continuation.finish(throwing: BenchmarkFailure.recognitionFailed) }
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(75))
            task.cancel()
            continuation.finish(throwing: BenchmarkFailure.timeout)
        }
        defer { feeder.cancel(); deadline.cancel(); task.cancel() }
        var firstPartial: Double?
        for try await (text, final, at) in stream {
            if firstPartial == nil, !final, !text.isEmpty { firstPartial = at - started }
            if final {
                guard let inputEnd else { throw BenchmarkFailure.recognitionFailed }
                return AppleBenchmarkResult(text: text, firstPartial: firstPartial,
                                            inputSeconds: inputEnd - started, totalSeconds: at - started)
            }
        }
        throw BenchmarkFailure.emptyResult
    }

    private static func feed(_ audio: BenchmarkAudio, to request: SFSpeechAudioBufferRecognitionRequest,
                             started: Double) async throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                         channels: 1, interleaved: false) else { throw BenchmarkFailure.invalidAudio }
        for offset in stride(from: 0, to: audio.samples.count, by: 1600) {
            try Task.checkCancellation()
            let count = min(1600, audio.samples.count - offset)
            let delay = started + Double(offset + count) / 16000 - benchmarkNow()
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let channels = buffer.floatChannelData else { throw BenchmarkFailure.invalidAudio }
            buffer.frameLength = AVAudioFrameCount(count)
            for index in 0..<count { channels[0][index] = audio.samples[offset + index] }
            request.append(buffer)
        }
    }
}

struct BenchmarkCloudConfiguration: Sendable {
    let speech: AzureWhisperConfig
    let refinement: AzureFoundryDeployment

    static func load() async throws -> Self {
        let runtime = try await DefaultPrivateModelConfigurationLoader(
            fileURL: ProtectedBenchmarkFiles.sandbox.appendingPathComponent("config.private.json")
        ).load(environment: [:])
        let values = runtime.environmentValues
        guard runtime.loadedPrivateFile, let root = values["AZURE_OPENAI_ENDPOINT"].flatMap(URL.init(string:)),
              let speechName = values["AZURE_TRANSCRIPTION_DEPLOYMENT"],
              let textName = values["AZURE_FOUNDRY_MODEL"], let key = values["whisperkey"] else {
            throw BenchmarkFailure.invalidConfiguration
        }
        var components = URLComponents(url: root.appendingPathComponent(
            "openai/deployments/\(speechName)/audio/transcriptions"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "api-version", value: "2024-02-01")]
        guard let endpoint = components?.url else { throw BenchmarkFailure.invalidConfiguration }
        return Self(speech: AzureWhisperConfig(endpoint: endpoint, apiKey: key),
                    refinement: AzureFoundryDeployment(name: "benchmark", endpoint: root, model: textName,
                        apiKey: key, authMode: .apiKey, apiStyle: .openAIV1, reasoningEffort: "none"))
    }
}

/// 只记录合并调用是否失败及返回长度，让生产合并器的回退可观察而不保存日志正文。
final class BenchmarkLLMService: LLMService {
    let base: DefaultLLMService
    private struct State: Sendable { var failed = false; var outputLength: Int? }
    private let state = Mutex(State())
    init(config: LLMProviderConfig) throws {
        base = DefaultLLMService(logger: SilentBenchmarkLogger(), azureFoundryConfig: config)
        try base.setProvider(config)
        base.setSkipContentAnalysis(true)
    }
    func reset() { state.withLock { $0 = State() } }
    func disposition(maxLength: Int) -> String {
        state.withLock { $0.failed ? "fallback_error" :
            (($0.outputLength ?? 0) > Int(Double(maxLength) * 1.5) ? "fallback_length" : "merged") }
    }
    func complete(prompt: String) async throws -> String {
        do {
            let result = try await base.complete(prompt: prompt)
            state.withLock { $0.outputLength = result.count }
            return result
        } catch { state.withLock { $0.failed = true }; throw BenchmarkFailure.recognitionFailed }
    }
    var availableProviders: [LLMProviderType] { base.availableProviders }
    var currentProvider: (any LLMProvider)? { base.currentProvider }
    var currentProviderType: LLMProviderType? { base.currentProviderType }
    func setProvider(_ config: LLMProviderConfig) throws { try base.setProvider(config) }
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        try await base.completeStreaming(prompt: prompt)
    }
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse { try await base.refine(request) }
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        try await base.refineStreaming(request)
    }
    func cancel() { base.cancel() }
    func validateCurrentProvider() async -> Bool { await base.validateCurrentProvider() }
}
#endif
