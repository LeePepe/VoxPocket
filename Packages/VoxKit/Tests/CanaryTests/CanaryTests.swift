import Testing
import VoxCore
import VoxWorkflow
import VoxWorkflowWhisperKit

@Test func allBuiltInWorkflowPresetsDoNotLeakCanaryContent() async throws {
    let canary = "workflow-transcript-canary"
    let logger = CanaryLogger()
    let telemetry = CanaryTelemetry()
    let runtime = WorkflowRuntime(logger: logger, telemetry: telemetry)
    for preset in [Preset.hybridAzure, Preset.appleSpeech, Preset.localWhisperKit, Preset.hybridLocal] {
        _ = try await runtime.execute(preset.speech, input: .string(canary))
        _ = try await runtime.execute(preset.refine, input: .string(canary))
    }
    #expect(logger.assertNoCanaryLeak(canaryStrings: [canary]))
    #expect(telemetry.assertNoCanaryLeak(canaryStrings: [canary]))
}
