import Testing
@testable import VoxPocket

struct TranscriberSelectionTests {
    @Test func defaultProviderSelectsLocalWhisperKit() {
        #expect(LLMAppConfig.defaultTranscriberProvider == .localWhisperKit)
    }
}
