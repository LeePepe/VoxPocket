import XCTest
import CoreFoundation
import Foundation
import Preferences
@testable import UIShared

@MainActor
final class PreferenceFixture {
    enum Rejection: Error {
        case collision
        case inconsistentMetadata
        case defaultsUnavailable
        case released
        case cleanupFailed(body: (any Error)?, cleanup: any Error)
    }

    let namespace: String
    private var active = true
    private var openedDefaults = false

    private init(namespace: String) {
        self.namespace = namespace
    }

    static func withFreshSuite(_ body: @MainActor (PreferenceFixture) async throws -> Void) async throws {
        try Task.checkCancellation()
        let namespace = "VoxPocket.UISharedTests.preference-fixture.\(UUID().uuidString)"
        try await requireVacant(namespace)
        try Task.checkCancellation()
        let fixture = PreferenceFixture(namespace: namespace)
        // 先绑定已签发记录的清理，再允许构造 defaults 或执行可能抛错的异步测试体。
        let cleanup = { try await fixture.cleanup() }
        let bodyFailure: (any Error)?
        do {
            try await body(fixture)
            bodyFailure = nil
        } catch {
            bodyFailure = error
        }
        do {
            _ = try await cleanup()
        } catch {
            throw Rejection.cleanupFailed(body: bodyFailure, cleanup: error)
        }
        if let bodyFailure { throw bodyFailure }
    }

    func defaults() throws -> sending UserDefaults {
        guard active else { throw Rejection.released }
        guard let defaults = UserDefaults(suiteName: namespace) else {
            throw Rejection.defaultsUnavailable
        }
        openedDefaults = true
        return defaults
    }

    // 碰撞控制只能检查本次已签发的记录，不能传入名称或签发第二份清理权限。
    func checkVacancy() async throws {
        try await Self.requireVacant(namespace)
    }

    func hasStoredKeys() async throws -> Bool {
        let counts = try await Self.keyCounts(namespace)
        return counts.contains { ($0 ?? 0) > 0 }
    }

    @discardableResult
    func cleanup() async throws -> Bool {
        // 返回值只表示本记录是否尝试清理，不声明落盘或同步成功；错误不重试。
        guard active else { return false }
        active = false
        guard openedDefaults else { return false }
        let namespace = namespace
        try await Task.detached {
            guard let defaults = UserDefaults(suiteName: namespace) else {
                throw Rejection.defaultsUnavailable
            }
            defaults.removePersistentDomain(forName: namespace)
        }.value
        return true
    }

    private nonisolated static func requireVacant(_ namespace: String) async throws {
        let first = try await keyCounts(namespace)
        guard !first.contains(where: { ($0 ?? 0) > 0 }) else { throw Rejection.collision }
        let second = try await keyCounts(namespace)
        guard !second.contains(where: { ($0 ?? 0) > 0 }) else { throw Rejection.collision }
        guard first == second else { throw Rejection.inconsistentMetadata }
    }

    private nonisolated static func keyCounts(_ namespace: String) async throws -> [Int?] {
        try await Task.detached {
            // 只取新名称的键数量，不读取值、枚举域、访问文件或强制同步。
            let anyHost = CFPreferencesCopyKeyList(namespace as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            var counts = [anyHost.map { CFArrayGetCount($0) }]
            #if os(macOS)
            let currentHost = CFPreferencesCopyKeyList(namespace as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            counts.append(currentHost.map { CFArrayGetCount($0) })
            #endif
            guard counts.allSatisfy({ ($0 ?? 0) >= 0 }) else { throw Rejection.inconsistentMetadata }
            return counts
        }.value
    }

    // nil/零只是未发现碰撞；UUID 不是系统预留，并发占用及异常退出仍有局限。
}

@MainActor
final class LLMProviderSettingsViewModelTests: XCTestCase {
    func testStageSelectionsPersistIndependentlyAndDefaultToRealtime() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let model = LLMProviderSettingsViewModel(preferences: store)
            await model.load()
            XCTAssertEqual(model.speechModel, .realtime)
            XCTAssertTrue(model.hasSpeechWarning)
            XCTAssertTrue(model.speechStatus.contains("回退"))
            await model.updateSpeechModel(.batch)
            await model.updateIntentModel(.azureFoundry)
            await model.updateToneModel(.appleIntelligence)
            await model.updateProvider(.appleIntelligence)
            await model.updateSkipContentAnalysis(true)
            let restored = LLMProviderSettingsViewModel(preferences: store)
            await restored.load()
            XCTAssertEqual(restored.speechModel, .batch)
            XCTAssertEqual(restored.intentModel, .azureFoundry)
            XCTAssertEqual(restored.toneModel, .appleIntelligence)
            XCTAssertEqual(restored.selectedProvider, .appleIntelligence)
            XCTAssertTrue(restored.skipContentAnalysis)
        }
    }

    func testDeploymentMustBeSavedAndValidBeforeShowingReady() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let model = LLMProviderSettingsViewModel(preferences: store, availability: .init(
                batchConfigured: true, realtimeCredentialsConfigured: true, textConfigured: true, textModelName: "fixture-text"
            ))
            await model.load()
            XCTAssertFalse(model.realtimeReady)
            model.realtimeDeploymentDraft = "fixture-live"
            XCTAssertFalse(model.realtimeReady)
            await model.load()
            XCTAssertEqual(model.realtimeDeploymentDraft, "fixture-live")
            await model.saveRealtimeDeployment()
            XCTAssertTrue(model.realtimeReady)
            model.realtimeDeploymentDraft = "https://invalid.example"
            await model.saveRealtimeDeployment()
            let stored: String? = await store.getValue(for: .realtimeDeployment)
            XCTAssertEqual(stored, "fixture-live")
            XCTAssertTrue(model.deploymentMessage?.contains("部署名") == true)
        }
    }

    func testLoadDefaultProviderIsAzureFoundry() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let viewModel = LLMProviderSettingsViewModel(preferences: store)

            await viewModel.load()

            XCTAssertEqual(viewModel.selectedProvider, .azureFoundry)
        }
    }

    func testUpdateProviderPersistsSelection() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            let viewModel = LLMProviderSettingsViewModel(preferences: store)

            await viewModel.updateProvider(.azureFoundry)

            let stored: String? = await store.getValue(for: .llmProvider)
            XCTAssertEqual(stored, LLMProviderSelection.azureFoundry.rawValue)
        }
    }

    func testSavedAppleSelectionIsNotOverwrittenByNewDefault() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            let store = UserDefaultsPreferencesStore(defaults: defaults)
            await store.setValue(LLMProviderSelection.appleIntelligence.rawValue, for: .llmProvider)
            let viewModel = LLMProviderSettingsViewModel(preferences: store)
            await viewModel.load()
            XCTAssertEqual(viewModel.selectedProvider, .appleIntelligence)
        }
    }
}

@MainActor
final class PreferenceFixtureTests: XCTestCase {
    private enum SetupFailure: Error { case intentional }

    func testFreshAllocationsAreDistinctAndCleanupIsScoped() async throws {
        try await PreferenceFixture.withFreshSuite { first in
            let firstDefaults = try first.defaults()
            try await PreferenceFixture.withFreshSuite { second in
                XCTAssertNotEqual(first.namespace, second.namespace)
                let firstHasKeys = try await first.hasStoredKeys()
                let secondHasKeys = try await second.hasStoredKeys()
                XCTAssertFalse(firstHasKeys)
                XCTAssertFalse(secondHasKeys)
                firstDefaults.set("fixture-survivor", forKey: "fixture-control")
                let secondDefaults = try second.defaults()
                secondDefaults.set("fixture-inner", forKey: "fixture-control")
            }
            XCTAssertEqual(firstDefaults.string(forKey: "fixture-control"), "fixture-survivor")
        }
    }

    func testCollisionCheckRefusesOwnedStateWithoutDeletingIt() async throws {
        try await PreferenceFixture.withFreshSuite { fixture in
            let defaults = try fixture.defaults()
            defaults.set("fixture-value", forKey: "fixture-control")
            do {
                try await fixture.checkVacancy()
                XCTFail("已签发测试域中的碰撞必须被拒绝")
            } catch PreferenceFixture.Rejection.collision {
                // 仅控制已签发的新域；拒绝不得删除其中的合成数据。
            }
            XCTAssertEqual(defaults.string(forKey: "fixture-control"), "fixture-value")
        }
    }

    func testNormalCompletionAwaitsWorkAndCleanupIsIdempotent() async throws {
        var issued: PreferenceFixture?
        try await PreferenceFixture.withFreshSuite { fixture in
            issued = fixture
            let defaults = try fixture.defaults()
            defaults.set("fixture-value", forKey: "fixture-control")
            await Task.yield()
            XCTAssertEqual(defaults.string(forKey: "fixture-control"), "fixture-value")
        }
        let fixture = try XCTUnwrap(issued)
        let hasKeys = try await fixture.hasStoredKeys()
        XCTAssertFalse(hasKeys)
        let cleanedAgain = try await fixture.cleanup()
        let cleanedTwice = try await fixture.cleanup()
        XCTAssertFalse(cleanedAgain)
        XCTAssertFalse(cleanedTwice)
        do {
            _ = try fixture.defaults()
            XCTFail("已结束的记录不得重新打开 defaults")
        } catch PreferenceFixture.Rejection.released {
            // 重复清理不能恢复使用权。
        }
    }

    func testThrowingPartialSetupCleansIssuedSuite() async throws {
        var issued: PreferenceFixture?
        do {
            try await PreferenceFixture.withFreshSuite { fixture in
                issued = fixture
                let defaults = try fixture.defaults()
                defaults.set("fixture-partial", forKey: "fixture-control")
                throw SetupFailure.intentional
            }
            XCTFail("部分初始化的错误必须保留")
        } catch SetupFailure.intentional {
            // 构造存储或 ViewModel 之前抛错，仍须结束这份分配的清理。
        }
        let fixture = try XCTUnwrap(issued)
        let hasKeys = try await fixture.hasStoredKeys()
        XCTAssertFalse(hasKeys)
    }
}
