import Foundation
import SwiftUI
import Testing
@testable import VoxPocket

@MainActor
struct AppStartupTests {
    @Test func serviceBackedContentIsLazyUntilReady() async {
        let loader = FakeStartupLoader()
        let startup = AppStartup(loadConfiguration: loader.load)
        var contentCreations = 0
        let view = AppStartupView(startup: startup) {
            contentCreations += 1
            return Text("Fixture content")
        }
        _ = view.body
        #expect(contentCreations == 0)
        let task = Task { await startup.prepare() }
        await loader.waitUntilStarted()
        _ = view.body
        #expect(contentCreations == 0)
        loader.finish()
        #expect(await task.value)
        _ = view.body
        #expect(contentCreations == 1)
    }

    @Test func failedConfigurationNeverConstructsServiceBackedContent() async {
        let startup = AppStartup { throw FakeStartupError.invalidConfiguration }
        #expect(await startup.prepare() == false)
        var contentCreations = 0
        let view = AppStartupView(startup: startup) {
            contentCreations += 1
            return Text("Fixture content")
        }
        _ = view.body
        #expect(contentCreations == 0)
    }

    @Test func configurationMustFinishBeforeServicesMayStart() async {
        let loader = FakeStartupLoader()
        let startup = AppStartup(loadConfiguration: loader.load)
        let first = Task { await startup.prepare() }
        await loader.waitUntilStarted()
        #expect(startup.phase == .loading)
        loader.finish()
        #expect(await first.value)
        #expect(startup.phase == .ready)
    }

    @Test func concurrentWindowsAndDelegateShareOneLoad() async {
        let loader = FakeStartupLoader()
        let startup = AppStartup(loadConfiguration: loader.load)
        let window = Task { await startup.prepare() }
        let delegate = Task { await startup.prepare() }
        await loader.waitUntilStarted()
        loader.finish()
        #expect(await window.value)
        #expect(await delegate.value)
        #expect(await startup.prepare())
        #expect(loader.calls == 1)
    }

    @Test func callerCancellationDoesNotCancelOtherEntryPoints() async {
        let loader = FakeStartupLoader()
        let startup = AppStartup(loadConfiguration: loader.load)
        let closedWindow = Task { await startup.prepare() }
        await loader.waitUntilStarted()
        closedWindow.cancel()
        let delegate = Task { await startup.prepare() }
        loader.finish()
        #expect(await delegate.value)
        #expect(startup.phase == .ready)
        #expect(loader.calls == 1)
    }

    @Test func invalidConfigurationStaysFailedWithoutFallbackOrRetry() async {
        var calls = 0
        let startup = AppStartup {
            calls += 1
            throw FakeStartupError.invalidConfiguration
        }
        #expect(await startup.prepare() == false)
        #expect(startup.phase == .failed)
        #expect(await startup.prepare() == false)
        #expect(calls == 1)
    }
}

private enum FakeStartupError: Error { case invalidConfiguration }

@MainActor
private final class FakeStartupLoader {
    var calls = 0
    private var completion: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func load() async throws {
        calls += 1
        await withCheckedContinuation { continuation in
            completion = continuation
            started?.resume()
            started = nil
        }
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
