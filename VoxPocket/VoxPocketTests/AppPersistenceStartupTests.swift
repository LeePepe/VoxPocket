import Foundation
import Testing
@testable import VoxPocket

@MainActor
struct AppPersistenceStartupTests {
    @Test func backgroundAndSaveShareOnePreparation() async {
        let startup = AppPersistenceStartup()
        let loader = FakePersistenceLoader()
        let background = Task { await startup.prepare(loader.load) }
        await loader.waitUntilStarted()
        let save = Task { await startup.prepare(loader.load) }
        loader.finish()
        #expect(await background.value)
        #expect(await save.value)
        #expect(await startup.prepare(loader.load))
        #expect(loader.calls == 1)
    }

    @Test func cancelledCallerDoesNotCancelStorePreparation() async {
        let startup = AppPersistenceStartup()
        let loader = FakePersistenceLoader()
        let caller = Task { await startup.prepare(loader.load) }
        await loader.waitUntilStarted()
        caller.cancel()
        let save = Task { await startup.prepare(loader.load) }
        loader.finish()
        #expect(await save.value)
        #expect(loader.calls == 1)
        #expect(!loader.wasCancelled)
    }

    @Test func failureDoesNotRepeatedlyOpenStore() async {
        let startup = AppPersistenceStartup()
        var attempts = 0
        #expect(await startup.prepare { attempts += 1; throw FakePersistenceError.unavailable } == false)
        #expect(await startup.prepare { attempts += 1 } == false)
        #expect(attempts == 1)
    }

    @Test func preparationWorksWithoutAnyWindow() async {
        let startup = AppPersistenceStartup()
        var prepared = false
        #expect(await startup.prepare { prepared = true })
        #expect(prepared)
    }
}

private enum FakePersistenceError: Error { case unavailable }

@MainActor
private final class FakePersistenceLoader {
    var calls = 0
    var wasCancelled = false
    private var completion: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func load() async throws {
        calls += 1
        await withCheckedContinuation { continuation in
            completion = continuation
            started?.resume()
            started = nil
        }
        wasCancelled = Task.isCancelled
    }

    func waitUntilStarted() async {
        guard completion == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        completion?.resume()
        completion = nil
    }
}
