import Testing
@testable import VoxPocket
import TranscriptionKit

struct TranscriberSelectionTests {
    @MainActor @Test func defaultProviderSelectsHybridLocalWhisper() {
        #expect(LLMAppConfig.defaultTranscriberProvider == .hybridLocalWhisper)
    }

    @MainActor @Test func quickTranscriberUsesDistinctCoordinatorInstance() {
        let main = ServiceContainer.makeTranscriber(preloadOnStart: true)
        let quick = ServiceContainer.makeQuickTranscriber()

        #expect(main is HybridLocalWhisperTranscriber)
        #expect(quick is HybridLocalWhisperTranscriber)
        #expect((main as AnyObject) !== (quick as AnyObject))
    }

    @MainActor @Test func quickTranscriberPreloadsLocalWhisperWhenAppStarts() throws {
        let quick = ServiceContainer.makeQuickTranscriber()
        let coordinator = try #require(quick as? HybridLocalWhisperTranscriber)
        let config = try #require(localWhisperConfig(from: coordinator))

        #expect(config.preloadOnStart)
    }

    @MainActor @Test func defaultConfigurationExposesLocalModelLoadingStatus() {
        #expect(ServiceContainer.shared.localModelLoadingObservable != nil)
    }
}

private func localWhisperConfig(
    from transcriber: HybridLocalWhisperTranscriber
) -> LocalWhisperKitConfig? {
    Mirror(reflecting: transcriber).children
        .first(where: { $0.label == "whisperConfig" })?
        .value as? LocalWhisperKitConfig
}
