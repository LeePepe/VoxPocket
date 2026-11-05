import Testing
@testable import VoxCore

@Test func canaryUtilitiesRecordAndRejectLeaks() {
    let logger = CanaryLogger()
    let telemetry = CanaryTelemetry()
    logger.info("recording.completed", fields: [.int("count", 1), .label("provider", .appleSpeech)])
    telemetry.record(VoxTelemetryEvent(name: "recording.completed", fields: [.durationMs("duration_ms", 2)]))
    #expect(logger.recordedMessages.count == 1)
    #expect(telemetry.recordedEvents.count == 1)
    #expect(logger.assertNoCanaryLeak(canaryStrings: ["transcript-canary"]))
    #expect(telemetry.assertNoCanaryLeak(canaryStrings: ["transcript-canary"]))
}

@Test func canaryUtilitiesInspectErrors() {
    let logger = CanaryLogger()
    let error = VoxKitError.llmRequestFailed(reason: .reason("safe-status"))
    #expect(logger.assertNoCanaryLeak(canaryStrings: ["transcript-canary"], error: error))
}
