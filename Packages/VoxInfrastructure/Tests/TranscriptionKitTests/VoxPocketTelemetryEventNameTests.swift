import Testing
import TranscriptionKit

struct VoxPocketTelemetryEventNameTests {
    @Test
    func publicNamesPreserveExactRawValues() {
        // 期望值独立写成字面量，不从生产定义生成。
        let expected: [(VoxPocketTelemetryEventName, String)] = [
            (.quickRecordFnReleased, "quick_record.fn_released"),
            (.quickRecordPanelClosed, "quick_record.panel_closed"),
            (.recordingStarted, "recording.started"),
            (.recordingStopped, "recording.stopped"),
            (.recordingDuration, "recording.duration"),
            (.transcriptionCompleted, "transcription.completed"),
            (.transcriptionFailed, "transcription.failed"),
            (.whisperModelLoaded, "whisper.model.loaded"),
            (.whisperModelLoadFailed, "whisper.model.load_failed"),
            (.refinementStarted, "refinement.started"),
            (.refinementCompleted, "refinement.completed"),
            (.refinementFailed, "refinement.failed"),
            (.undoPerformed, "history.undo"),
            (.redoPerformed, "history.redo"),
            (.sessionCreated, "session.created"),
            (.sessionDeleted, "session.deleted"),
        ]

        for (event, rawValue) in expected {
            #expect(event.rawValue == rawValue)
            #expect(VoxPocketTelemetryEventName(rawValue: rawValue) == event)
            #expect(requireSendable(event).rawValue == rawValue)
        }

        #expect(Set(expected.map { $0.0.rawValue }).count == 16)
        #expect(VoxPocketTelemetryEventName(rawValue: "unknown.telemetry.event") == nil)
    }

    private func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
