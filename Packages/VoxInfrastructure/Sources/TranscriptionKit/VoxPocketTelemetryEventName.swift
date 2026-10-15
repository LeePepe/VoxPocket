/// VoxPocket 拥有的遥测事件名称。
public enum VoxPocketTelemetryEventName: String, Sendable {
    case recordingStarted = "recording.started"
    case recordingStopped = "recording.stopped"
    case recordingDuration = "recording.duration"
    case transcriptionCompleted = "transcription.completed"
    case transcriptionFailed = "transcription.failed"
    case whisperModelLoaded = "whisper.model.loaded"
    case whisperModelLoadFailed = "whisper.model.load_failed"
    case refinementStarted = "refinement.started"
    case refinementCompleted = "refinement.completed"
    case refinementFailed = "refinement.failed"
    case undoPerformed = "history.undo"
    case redoPerformed = "history.redo"
    case sessionCreated = "session.created"
    case sessionDeleted = "session.deleted"
}

/// 转录失败遥测允许的固定分类。
public enum VoxPocketTranscriptionFailureCategory: String, Sendable {
    case modelPreparation = "model_preparation"
    case streamingStart = "streaming_start"
}
