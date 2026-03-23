import Testing
@testable import VoxPocket
import TranscriptionKit

struct TranscriberSelectionTests {
    @MainActor @Test func defaultProviderSelectsLocalWhisperKit() {
        #expect(LLMAppConfig.defaultTranscriberProvider == .localWhisperKit)
    }

    @MainActor @Test func quickTranscriberUsesDistinctCoordinatorInstance() {
        let main = ServiceContainer.makeTranscriber(preloadOnStart: true)
        let quick = ServiceContainer.makeQuickTranscriber()

        #expect(main is LoadingFallbackTranscriptionCoordinator)
        #expect(quick is LoadingFallbackTranscriptionCoordinator)
        #expect((main as AnyObject) !== (quick as AnyObject))
    }

    @MainActor @Test func quickTranscriberPreloadsLocalWhisperWhenAppStarts() throws {
        let quick = ServiceContainer.makeQuickTranscriber()
        let coordinator = try #require(quick as? LoadingFallbackTranscriptionCoordinator)
        let config = try #require(localWhisperConfig(from: coordinator))

        #expect(config.preloadOnStart)
    }

    @MainActor @Test func defaultConfigurationExposesLocalModelLoadingStatus() {
        #expect(ServiceContainer.shared.localModelLoadingObservable != nil)
    }
}

private func localWhisperConfig(
    from transcriber: LoadingFallbackTranscriptionCoordinator
) -> LocalWhisperKitConfig? {
    guard let primary = Mirror(reflecting: transcriber).children
        .first(where: { $0.label == "primary" })?.value as? WhisperKitTranscriber else {
        return nil
    }

    return Mirror(reflecting: primary).children
        .first(where: { $0.label == "config" })?
        .value as? LocalWhisperKitConfig
}
