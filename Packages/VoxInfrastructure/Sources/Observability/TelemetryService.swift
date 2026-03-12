import Foundation

/// 遥测事件
public struct TelemetryEvent: Sendable {
    /// 事件名称
    public let name: String
    /// 事件属性
    public let properties: [String: String]
    /// 时间戳
    public let timestamp: Date

    public init(
        name: String,
        properties: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

/// 预定义的遥测事件名称
public enum TelemetryEventName: String, Sendable {
    // 录音相关
    case recordingStarted = "recording.started"
    case recordingStopped = "recording.stopped"
    case recordingDuration = "recording.duration"

    // 转录相关
    case transcriptionCompleted = "transcription.completed"
    case transcriptionFailed = "transcription.failed"
    case whisperModelLoaded = "whisper.model.loaded"
    case whisperModelLoadFailed = "whisper.model.load_failed"

    // LLM 相关
    case refinementStarted = "refinement.started"
    case refinementCompleted = "refinement.completed"
    case refinementFailed = "refinement.failed"

    // 历史相关
    case undoPerformed = "history.undo"
    case redoPerformed = "history.redo"

    // 会话相关
    case sessionCreated = "session.created"
    case sessionDeleted = "session.deleted"
}

/// 遥测服务协议
///
/// 提供匿名使用数据收集接口（需用户明确同意）。
public protocol TelemetryService: AnyObject, Sendable {

    /// 是否启用遥测
    var isEnabled: Bool { get set }

    /// 追踪事件
    ///
    /// - Parameter event: 遥测事件
    func track(_ event: TelemetryEvent)

    /// 追踪事件（便捷方法）
    ///
    /// - Parameters:
    ///   - name: 事件名称
    ///   - properties: 事件属性
    func track(name: String, properties: [String: String])

    /// 刷新待发送的事件
    func flush() async

    /// 重置用户标识
    func resetIdentifier()
}

// MARK: - 便捷方法扩展

public extension TelemetryService {

    /// 追踪事件（无属性）
    func track(name: String) {
        track(name: name, properties: [:])
    }
}

/// 默认空实现，避免在未接入具体遥测系统时传播条件分支。
public final class NoopTelemetryService: TelemetryService, @unchecked Sendable {
    public var isEnabled: Bool = false

    public init() {}

    public func track(_ event: TelemetryEvent) {}

    public func track(name: String, properties: [String: String]) {}

    public func flush() async {}

    public func resetIdentifier() {}
}
