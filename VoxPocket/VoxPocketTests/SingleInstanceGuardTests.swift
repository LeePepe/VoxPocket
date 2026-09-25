//
//  SingleInstanceGuardTests.swift
//  VoxPocketTests
//
//  MY-1303: 单实例保护判定逻辑测试
//

#if os(macOS)
import Testing
import Foundation
@testable import VoxPocket

struct SingleInstanceGuardTests {

    struct FakeRunningInstance: RunningInstance {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        func activate() {}
    }

    @Test("Only self running → proceed")
    func onlySelfProceeds() {
        let apps: [RunningInstance] = [
            FakeRunningInstance(processIdentifier: 111, bundleIdentifier: "com.leepepe.voxpocket")
        ]
        let decision = SingleInstanceGuard.decide(
            bundleId: "com.leepepe.voxpocket",
            currentPid: 111,
            runningApps: apps
        )
        #expect(decision == .proceed)
    }

    @Test("Another instance same bundle → block with that pid")
    func anotherInstanceIsDetected() {
        let apps: [RunningInstance] = [
            FakeRunningInstance(processIdentifier: 111, bundleIdentifier: "com.leepepe.voxpocket"),
            FakeRunningInstance(processIdentifier: 222, bundleIdentifier: "com.leepepe.voxpocket")
        ]
        let decision = SingleInstanceGuard.decide(
            bundleId: "com.leepepe.voxpocket",
            currentPid: 111,
            runningApps: apps
        )
        #expect(decision == .another(pid: 222))
    }

    @Test("Different bundle ids do not conflict")
    func differentBundleIgnored() {
        let apps: [RunningInstance] = [
            FakeRunningInstance(processIdentifier: 111, bundleIdentifier: "com.leepepe.voxpocket"),
            FakeRunningInstance(processIdentifier: 333, bundleIdentifier: "com.apple.finder"),
            FakeRunningInstance(processIdentifier: 444, bundleIdentifier: nil)
        ]
        let decision = SingleInstanceGuard.decide(
            bundleId: "com.leepepe.voxpocket",
            currentPid: 111,
            runningApps: apps
        )
        #expect(decision == .proceed)
    }

    @Test("Empty running list → proceed")
    func emptyListProceeds() {
        let decision = SingleInstanceGuard.decide(
            bundleId: "com.leepepe.voxpocket",
            currentPid: 111,
            runningApps: []
        )
        #expect(decision == .proceed)
    }

    @Test("Self excluded by pid even if bundle matches twice by accident")
    func selfExcludedByPid() {
        // 只有自己，bundleId 匹配也应 proceed（pid 排自己）
        let apps: [RunningInstance] = [
            FakeRunningInstance(processIdentifier: 500, bundleIdentifier: "com.leepepe.voxpocket")
        ]
        let decision = SingleInstanceGuard.decide(
            bundleId: "com.leepepe.voxpocket",
            currentPid: 500,
            runningApps: apps
        )
        #expect(decision == .proceed)
    }

    @Test("First other match wins (deterministic)")
    func firstMatchWins() {
        let apps: [RunningInstance] = [
            FakeRunningInstance(processIdentifier: 111, bundleIdentifier: "com.leepepe.voxpocket"),
            FakeRunningInstance(processIdentifier: 222, bundleIdentifier: "com.leepepe.voxpocket"),
            FakeRunningInstance(processIdentifier: 333, bundleIdentifier: "com.leepepe.voxpocket")
        ]
        let decision = SingleInstanceGuard.decide(
            bundleId: "com.leepepe.voxpocket",
            currentPid: 111,
            runningApps: apps
        )
        #expect(decision == .another(pid: 222))
    }
}
#endif
