import Foundation

/// 松手时冻结的来源资格；不携带用户文本。
public struct QuickRecordingReleaseSnapshot: Sendable, Equatable {
    public let sessionID: UUID
    public let hasRecognizedSpeech: Bool

    public init(sessionID: UUID, hasRecognizedSpeech: Bool) {
        self.sessionID = sessionID
        self.hasRecognizedSpeech = hasRecognizedSpeech
    }
}

public enum QuickRecordingReleaseError: Error, Sendable {
    case unsupported
    case noPreparedSession
}

/// prepare 必须先于启动首次挂起；freeze 同步执行，complete 等待同一会话收尾。
public protocol QuickRecordingReleaseControlling: AnyObject, Sendable {
    func prepareQuickRecording() throws
    func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot
    /// 首次 complete 可将同一 token 降级为 false；冻结的 false 不得升级。
    func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws
}

/// 可注入的录音边界；生产默认仍使用原有 Apple/Whisper 适配器。
/// callback 由真实识别回调和确定性测试共用，避免测试复制资格判断。
struct QuickRecordingSessionEffects: Sendable {
    typealias ResultHandler = @Sendable (TranscriptionResult) -> Void
    let start: @Sendable (UUID, Locale, @escaping ResultHandler) async throws -> Void
    let stopCapture: @Sendable () async -> URL?
    let endAppleAudio: @Sendable () -> Void
    let cancelApple: @Sendable () -> Void
    let cancelRealtime: @Sendable () async -> Void
    let removeAudio: @Sendable (URL?) async throws -> Void
    let finalize: @Sendable (Locale) async throws -> String
}

/// Await transport teardown before the pipeline schedules its idempotent cancellation.
func cancelQuickRecordingRealtime(_ pipeline: RealtimeAudioPipeline,
                                  session: DefaultRealtimeTranscriptionSession) async {
    await session.cancel()
    pipeline.cancel()
}
