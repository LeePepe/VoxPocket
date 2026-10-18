import Foundation
import SwiftUI
import Testing
#if !SWIFT_PACKAGE
import LokiKit
import Preferences
#endif
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

    @Test func configurationReadyCompletionIsSharedAndAwaited() async {
        let completionGate = FakeStartupLoader()
        var completions = 0
        var returned = 0
        let startup = AppStartup(configurationReady: {
            completions += 1
            do { try await completionGate.load() } catch { Issue.record(error) }
        }, loadConfiguration: {})
        let first = Task {
            let prepared = await startup.prepare()
            returned += 1
            return prepared
        }
        await completionGate.waitUntilStarted()
        let (entered, continuation) = AsyncStream<Void>.makeStream()
        let second = Task {
            continuation.yield()
            let prepared = await startup.prepare()
            returned += 1
            return prepared
        }
        for await _ in entered { break }
        #expect(returned == 0)
        #expect(completions == 1)
        completionGate.finish()
        #expect(await first.value)
        #expect(await second.value)
        #expect(await startup.prepare())
        #expect(returned == 2)
        #expect(completions == 1)
    }

    // 轻量 SwiftPM 启动探针不包含真实容器；这些集成断言由 App XCTest 执行。
    #if !SWIFT_PACKAGE
    @Test func persistedConsentStartsOncePerFreshLifetimeAfterConfiguration() async throws {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        await fixture.preferences.persistConsent(true)
        assertNoTelemetryWork(fixture)

        let firstIdentity = try await prepareTelemetryLifetime(fixture, lifetime: 1)
        let storedIdentity = try #require(persistedIdentity(in: fixture))
        let secondIdentity = try await prepareTelemetryLifetime(fixture, lifetime: 2)

        #expect(firstIdentity == secondIdentity)
        #expect(persistedIdentity(in: fixture) == storedIdentity)
        #expect(fixture.identities == [firstIdentity, firstIdentity])
        #expect(await fixture.preferences.isConsented)
    }

    private func prepareTelemetryLifetime(_ fixture: RuntimeFixture, lifetime: Int) async throws -> UUID {
        let loader = FakeStartupLoader()
        let previousOperations = fixture.recorder.operations
        let previousIdentities = fixture.identities
        let previousIdentity = persistedIdentity(in: fixture)
        let startedAt = ContinuousClock.now
        var completions = 0
        var container: ServiceContainer?
        let startup = AppStartup(configurationReady: {
            completions += 1
            let readyContainer = fixture.makeContainer(notificationCenter: NotificationCenter())
            container = readyContainer
            await readyContainer.completeProductTelemetryStartup(startedAt: startedAt)
        }, loadConfiguration: loader.load)
        let first = Task { await startup.prepare() }
        let second = Task { await startup.prepare() }
        await loader.waitUntilStarted()
        #expect(startup.phase == .loading)
        #expect(container == nil)
        #expect(completions == 0)
        #expect(fixture.identities == previousIdentities)
        #expect(persistedIdentity(in: fixture) == previousIdentity)
        #expect(fixture.recorder.constructionCount == lifetime - 1)
        #expect(fixture.recorder.events.count == lifetime - 1)
        #expect(fixture.recorder.operations == previousOperations)
        loader.finish()
        #expect(await first.value)
        #expect(await second.value)
        #expect(await startup.prepare())
        let readyContainer = try #require(container)
        await readyContainer.waitForPendingProductTelemetryStartupCompletion()
        #expect(startup.phase == .ready)
        #expect(loader.calls == 1)
        #expect(completions == 1)
        #expect(fixture.recorder.constructionCount == lifetime)
        #expect(fixture.identities.count == lifetime)
        #expect(fixture.recorder.events.count == lifetime)
        #expect(fixture.recorder.operations == Array(repeating: [
            "construct", "track product.performance", "flush"
        ], count: lifetime).flatMap { $0 })
        try assertAppLaunchEvent(fixture)
        return try #require(fixture.identities.last)
    }

    private func assertAppLaunchEvent(_ fixture: RuntimeFixture) throws {
        let event = try #require(fixture.recorder.events.last)
        #expect(event.name == "product.performance")
        #expect(event.properties["operation"] == "app_launch")
        #expect(Set(event.properties.keys) == ["operation", "duration_ms"])
        let duration = try #require(Double(event.properties["duration_ms"] ?? ""))
        #expect((0...3_600_000).contains(duration))
    }

    @Test func failedConfigurationNeverInvokesTelemetryCompletion() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        await fixture.preferences.persistConsent(true)
        var completions = 0
        let startup = AppStartup(configurationReady: {
            completions += 1
            let container = fixture.makeContainer(notificationCenter: NotificationCenter())
            await container.completeProductTelemetryStartup(startedAt: .now)
        }, loadConfiguration: { throw FakeStartupError.invalidConfiguration })

        #expect(await startup.prepare() == false)
        #expect(await startup.prepare() == false)
        #expect(startup.phase == .failed)
        #expect(completions == 0)
        #expect(await fixture.preferences.isConsented)
        assertNoTelemetryWork(fixture)
    }

    @Test func defaultOffStartupCompletionPerformsNoTelemetryWork() async throws {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        try await prepareInactiveTelemetry(fixture) {
            fixture.makeContainer(notificationCenter: NotificationCenter())
        }
        #expect(await fixture.preferences.isConsented == false)
    }

    @Test func excludedHostsStartupCompletionPerformsNoTelemetryWork() async throws {
        for host in BlobTelemetryHostKind.allCases where host != .interactiveApplication {
            let fixture = RuntimeFixture()
            defer { fixture.remove() }
            await fixture.preferences.persistConsent(true)
            try await prepareInactiveTelemetry(fixture) {
                excludedHostContainer(fixture, host: host)
            }
            #expect(await fixture.preferences.isConsented)
        }
    }

    private func prepareInactiveTelemetry(
        _ fixture: RuntimeFixture,
        makeContainer: @escaping @MainActor () -> ServiceContainer
    ) async throws {
        let loader = FakeStartupLoader()
        var completions = 0
        var container: ServiceContainer?
        let startup = AppStartup(configurationReady: {
            completions += 1
            let readyContainer = makeContainer()
            container = readyContainer
            await readyContainer.completeProductTelemetryStartup(startedAt: .now)
        }, loadConfiguration: loader.load)
        let preparation = Task { await startup.prepare() }
        await loader.waitUntilStarted()
        #expect(container == nil)
        #expect(completions == 0)
        assertNoTelemetryWork(fixture)
        loader.finish()
        #expect(await preparation.value)
        #expect(await startup.prepare())
        let readyContainer = try #require(container)
        await readyContainer.waitForPendingProductTelemetryStartupCompletion()
        #expect(completions == 1)
        #expect(loader.calls == 1)
        assertNoTelemetryWork(fixture)
    }

    private func excludedHostContainer(_ fixture: RuntimeFixture, host: BlobTelemetryHostKind) -> ServiceContainer {
        let configuration = BlobTelemetryConfiguration.enabled(.init(
            endpoint: URL(string: "https://telemetry.example.invalid/container")!,
            sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
        ))
        return ServiceContainer(
            productTelemetryPreferences: fixture.preferences,
            processEnvironment: [:],
            processArguments: [],
            productTelemetryConfiguration: { configuration },
            productTelemetryBootstrapFactory: { _ in
                Issue.record("Excluded host must not request identity or bootstrap")
                return .testing(configuration: configuration, host: host, isConsented: true,
                                makeService: { fixture.recorder.construct() })
            },
            productTelemetryNotificationCenter: NotificationCenter(),
            productTelemetryHostOverride: host
        )
    }

    private func assertNoTelemetryWork(_ fixture: RuntimeFixture) {
        #expect(persistedIdentity(in: fixture) == nil)
        #expect(fixture.identities.isEmpty)
        #expect(fixture.recorder.constructionCount == 0)
        #expect(fixture.recorder.events.isEmpty)
        #expect(fixture.recorder.operations.isEmpty)
    }

    private func persistedIdentity(in fixture: RuntimeFixture) -> Data? {
        UserDefaults(suiteName: fixture.suite)?.data(forKey: "telemetry.product.installIdentity")
    }
    #endif
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
