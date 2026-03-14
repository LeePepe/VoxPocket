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
}
