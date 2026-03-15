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
        let primary = try #require(primaryCoordinator(from: coordinator) as? WhisperKitTranscriber)
        let config = try #require(localWhisperConfig(from: primary))

        #expect(config.preloadOnStart)
    }
}

private func primaryCoordinator(
    from coordinator: LoadingFallbackTranscriptionCoordinator
) -> (any TranscriptionCoordinator)? {
    Mirror(reflecting: coordinator).children
        .first(where: { $0.label == "primary" })?
        .value as? any TranscriptionCoordinator
}

private func localWhisperConfig(
    from transcriber: WhisperKitTranscriber
) -> LocalWhisperKitConfig? {
    Mirror(reflecting: transcriber).children
        .first(where: { $0.label == "config" })?
        .value as? LocalWhisperKitConfig
}
