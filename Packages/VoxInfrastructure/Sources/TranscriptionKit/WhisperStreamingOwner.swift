import Foundation
import Synchronization
import VoxCore
#if canImport(WhisperKit)
import WhisperKit

final class WhisperStreamControl: Sendable {
    struct State: Sendable {
        var stopped = false
        var paused = false
    }
    let state = Mutex(State())
}

actor WhisperStreamingOwner {
    private let storage: Mutex<WhisperKit?>
    private var operation: Task<Void, Error>?
    init(pipeline: sending WhisperKit) { storage = Mutex(pipeline) }

    func start(languageCode: String?, control: WhisperStreamControl,
               onPartial: @escaping @Sendable (String) -> Void,
               onAudioLevel: @escaping @Sendable (Float) -> Void) async throws {
        let pipeline = take()
        guard let pipeline else { throw VoxKitError.modelNotReady }
        let started = AsyncThrowingStream<Void, Error>.makeStream()
        let transfer = Mutex<WhisperKit?>(pipeline)
        operation = Task.detached { [self] in
            let pipeline = transfer.withLock { state in
                let pipeline = state
                state = nil
                return pipeline
            }
            guard let pipeline else { throw VoxKitError.modelNotReady }
            try await Self.stream(pipeline: pipeline, languageCode: languageCode, control: control,
                onPartial: onPartial, onAudioLevel: onAudioLevel, started: started.continuation, owner: self)
        }
        for try await _ in started.stream { break }
    }
    func run() async throws -> sending WhisperKit {
        try await operation?.value
        guard let pipeline = take() else { throw VoxKitError.modelNotReady }
        return pipeline
    }
    func recover() async -> sending WhisperKit? { take() }
    private nonisolated func take() -> sending WhisperKit? {
        storage.withLock { state in
            let pipeline = state
            state = nil
            return pipeline
        }
    }
    private nonisolated func restore(_ pipeline: sending WhisperKit) {
        let transfer = Mutex<WhisperKit?>(pipeline)
        storage.withLock { state in
            state = transfer.withLock { source in
                let pipeline = source
                source = nil
                return pipeline
            }
        }
    }
    private nonisolated static func shouldStopEarly(_ progress: TranscriptionProgress, options: DecodingOptions) -> Bool? {
        if progress.tokens.count > 60 {
            let compression = TextUtilities.compressionRatio(of: Array(progress.tokens.suffix(60)))
            if compression > options.compressionRatioThreshold ?? 0 { return false }
        }
        if let logProbability = progress.avgLogprob, let threshold = options.logProbThreshold,
           logProbability < threshold { return false }
        return nil
    }

    private nonisolated static func stream(pipeline: sending WhisperKit, languageCode: String?,
        control: WhisperStreamControl, onPartial: @escaping @Sendable (String) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        started: AsyncThrowingStream<Void, Error>.Continuation, owner: WhisperStreamingOwner) async throws {
        do {
            try pipeline.audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
            started.yield(())
            started.finish()
            let state = WhisperStreamingState()
            var paused = false
            let task = TranscribeTask(currentTimings: TranscriptionTimings(), progress: Progress(),
                audioProcessor: pipeline.audioProcessor, audioEncoder: pipeline.audioEncoder,
                featureExtractor: pipeline.featureExtractor, segmentSeeker: pipeline.segmentSeeker,
                textDecoder: pipeline.textDecoder, tokenizer: try pipeline.tokenizerRequired())
            while !control.state.withLock({ $0.stopped }) {
                try Task.checkCancellation()
                let shouldPause = control.state.withLock { $0.paused }
                if shouldPause != paused {
                    if shouldPause { pipeline.audioProcessor.pauseRecording() }
                    else { try pipeline.audioProcessor.resumeRecordingLive(inputDeviceID: nil, callback: nil) }
                    paused = shouldPause
                }
                onAudioLevel(pipeline.audioProcessor.relativeEnergy.last ?? 0)
                let samples = Array(pipeline.audioProcessor.audioSamples)
                let seconds = state.secondsSinceLastDecode(sampleCount: samples.count)
                guard !paused, seconds > 1,
                      AudioProcessor.isVoiceDetected(in: pipeline.audioProcessor.relativeEnergy,
                          nextBufferInSeconds: seconds, silenceThreshold: 0.3) else {
                    try await Task.sleep(for: .milliseconds(100))
                    continue
                }
                var options = DecodingOptions()
                options.language = languageCode
                options.clipTimestamps = [state.beginDecode(sampleCount: samples.count)]
                let result = try await task.run(audioArray: samples, decodeOptions: options) { progress in
                    onPartial(state.receive(progress))
                    return Self.shouldStopEarly(progress, options: options)
                }
                onPartial(state.confirm(result.segments))
            }
            pipeline.audioProcessor.stopRecording()
            owner.restore(pipeline)
        } catch {
            pipeline.audioProcessor.stopRecording()
            started.finish(throwing: error)
            owner.restore(pipeline)
            throw error
        }
    }
}
#endif
