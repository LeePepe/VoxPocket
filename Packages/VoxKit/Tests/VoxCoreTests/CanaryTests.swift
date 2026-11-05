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
    let telemetry = CanaryTelemetry()
    let error = VoxKitError.llmRequestFailed(reason: .reason("transcript-canary"))
    #expect(!logger.assertNoCanaryLeak(canaryStrings: ["transcript-canary"], error: error))
    #expect(!telemetry.assertNoCanaryLeak(canaryStrings: ["transcript-canary"], error: error))
}

@Test func canaryUtilitiesRejectContaminatedMessagesFieldsAndEvents() {
    let logger = CanaryLogger()
    logger.info("transcript-canary")
    #expect(!logger.assertNoCanaryLeak(canaryStrings: ["transcript-canary"]))

    let fieldLogger = CanaryLogger()
    fieldLogger.info("safe", fields: [.label("transcript-canary", .source("safe")), .label("safe", .source("transcript-canary"))])
    #expect(!fieldLogger.assertNoCanaryLeak(canaryStrings: ["transcript-canary"]))

    let telemetry = CanaryTelemetry()
    telemetry.record(VoxTelemetryEvent(name: "transcript-canary"))
    #expect(!telemetry.assertNoCanaryLeak(canaryStrings: ["transcript-canary"]))
}
