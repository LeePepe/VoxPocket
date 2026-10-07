import LokiKit
import TranscriptionKit
import XCTest

final class LegacyTelemetryEventNameCompatibilityTests: XCTestCase {
    func testPublicLegacyNamesPreserveExactRawValues() {
        // 保留对旧 SDK 全部公共 case 的显式引用和独立字面量期望。
        let expected: [(TelemetryEventName, String)] = [
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
            XCTAssertEqual(event.rawValue, rawValue)
            XCTAssertEqual(TelemetryEventName(rawValue: rawValue), event)
            XCTAssertEqual(requireSendable(event).rawValue, rawValue)
        }

        XCTAssertEqual(Set(expected.map { $0.0.rawValue }).count, 14)
        XCTAssertNil(TelemetryEventName(rawValue: "unknown.telemetry.event"))
    }

    private func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
