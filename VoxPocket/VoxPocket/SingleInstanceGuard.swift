//
//  SingleInstanceGuard.swift
//  VoxPocket
//
//  单实例保护：启动时若已有同 bundleId 的其他 VoxPocket 进程在跑，
//  激活已有实例并放弃自身启动，避免两个实例都注册 Fn 全局热键
//  导致按一次 Fn 弹出两个 panel。
//

#if os(macOS)
import Foundation
import AppKit

/// 运行中进程的最小信息，用于单实例判定。
///
/// 抽象出协议是为了让 `SingleInstanceGuard` 的判定逻辑可单测 ——
/// 生产代码用 `NSRunningApplication` 作实现，测试用 fake。
public protocol RunningInstance {
    var processIdentifier: pid_t { get }
    var bundleIdentifier: String? { get }
    /// 尝试把该实例激活到前台。生产实现委托给 `NSRunningApplication.activate(options:)`。
    func activate()
}

/// 单实例判定与激活逻辑（纯函数式，无副作用外部依赖）。
public enum SingleInstanceGuard {

    /// 单实例检查结果。
    public enum Decision: Equatable {
        /// 当前进程是唯一实例，正常继续启动。
        case proceed
        /// 已有实例在跑，本进程应放弃启动。
        case another(pid: pid_t)
    }

    /// 基于给定的运行进程快照做单实例判定。
    ///
    /// - Parameters:
    ///   - bundleId: 本 app 的 bundle identifier
    ///   - currentPid: 当前进程 pid（用于排除自己）
    ///   - runningApps: 当前系统上运行的所有 app（含本进程）
    /// - Returns: `proceed` 或 `another(pid:)`
    public static func decide(
        bundleId: String,
        currentPid: pid_t,
        runningApps: [RunningInstance]
    ) -> Decision {
        for app in runningApps {
            guard app.processIdentifier != currentPid else { continue }
            guard app.bundleIdentifier == bundleId else { continue }
            return .another(pid: app.processIdentifier)
        }
        return .proceed
    }

    /// 生产入口：查询 `NSWorkspace` 拿到当前 running apps，做判定，
    /// 若发现已有实例则激活它并返回 `.another(pid:)`；否则 `.proceed`。
    ///
    /// 副作用：只在返回 `.another` 时尝试激活已有实例；不 terminate 自己（由调用方处理）。
    @MainActor
    public static func evaluateAndActivateExisting(
        bundleId: String,
        currentPid: pid_t = ProcessInfo.processInfo.processIdentifier,
        workspace: NSWorkspace = .shared
    ) -> Decision {
        let apps = workspace.runningApplications.map(NSRunningApplicationAdapter.init(app:))
        let decision = decide(
            bundleId: bundleId,
            currentPid: currentPid,
            runningApps: apps
        )
        if case .another(let pid) = decision {
            if let existing = workspace.runningApplications.first(where: { $0.processIdentifier == pid }) {
                existing.activate(options: [.activateAllWindows])
            }
        }
        return decision
    }
}

/// 生产 `RunningInstance` 实现，桥接 `NSRunningApplication`。
struct NSRunningApplicationAdapter: RunningInstance {
    let app: NSRunningApplication
    var processIdentifier: pid_t { app.processIdentifier }
    var bundleIdentifier: String? { app.bundleIdentifier }
    func activate() {
        app.activate(options: [.activateAllWindows])
    }
}
#endif
