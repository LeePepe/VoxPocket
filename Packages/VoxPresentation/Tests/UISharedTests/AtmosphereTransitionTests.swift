import XCTest
@testable import UIShared

/// 守护「阶段流转」动效曲线：交叉淡出、入场呼吸、完成安定内收。
/// 这些是纯函数，逐帧渲染无法在 CI 里回放，故用确定性断言锁住动效手感。
final class AtmosphereTransitionTests: XCTestCase {

    // MARK: - 交叉淡出（色彩 morph 而非硬切）

    func testCrossfadeStartsAtZeroEndsAtOne() {
        XCTAssertEqual(AtmosphereTransition.crossfade(elapsed: 0, duration: 0.72), 0, accuracy: 0.0001)
        XCTAssertEqual(AtmosphereTransition.crossfade(elapsed: 0.72, duration: 0.72), 1, accuracy: 0.0001)
    }

    func testCrossfadeIsMonotonicAndClamped() {
        var last = -1.0
        for i in 0...12 {
            let t = Double(i) / 12 * 0.72
            let v = AtmosphereTransition.crossfade(elapsed: t, duration: 0.72)
            XCTAssertGreaterThanOrEqual(v, last, "交叉淡出必须单调不减")
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
            last = v
        }
        // 超出窗口仍夹在 1，不回弹
        XCTAssertEqual(AtmosphereTransition.crossfade(elapsed: 5, duration: 0.72), 1, accuracy: 0.0001)
    }

    func testCrossfadeMidpointIsSmoothstepNotLinear() {
        // smoothstep(0.5) == 0.5，但两端更缓；取 1/4 处应低于线性 0.25
        let quarter = AtmosphereTransition.crossfade(elapsed: 0.18, duration: 0.72)
        XCTAssertLessThan(quarter, 0.25, "应为 smoothstep（起步更缓），而非线性")
    }

    func testCrossfadeZeroDurationIsInstant() {
        XCTAssertEqual(AtmosphereTransition.crossfade(elapsed: 0, duration: 0), 1, accuracy: 0.0001)
    }

    // MARK: - 玻璃配色（宝石柔调多彩 + 色心偏移）

    func testEachStageHasFiveBlobs() {
        for status in RecorderStatus.allCases {
            XCTAssertEqual(AtmosphereGlass.blobs(for: status).count, 5, "\(status) 应有 5 个光团")
            XCTAssertEqual(AtmosphereGlass.colors(for: status).count, 5, "\(status) 应有 5 个颜色")
        }
    }

    func testBlobLayoutIsSharedAcrossStages() {
        // 布局固定，阶段间只 morph 颜色 → 位置/尺寸一致
        let listening = AtmosphereGlass.blobs(for: .listening)
        let refining = AtmosphereGlass.blobs(for: .refining)
        for (a, b) in zip(listening, refining) {
            XCTAssertEqual(a.x, b.x, accuracy: 0.0001)
            XCTAssertEqual(a.y, b.y, accuracy: 0.0001)
            XCTAssertEqual(a.scale, b.scale, accuracy: 0.0001)
        }
    }

    func testStagesAreVisuallyDistinct() {
        // 主要阶段的配色应各不相同（色心偏移 → 阶段可区分）
        let listening = AtmosphereGlass.colors(for: .listening)
        let refining = AtmosphereGlass.colors(for: .refining)
        let done = AtmosphereGlass.colors(for: .done)
        XCTAssertNotEqual(listening, refining, "识别与分析配色应不同")
        XCTAssertNotEqual(refining, done, "分析与结果配色应不同")
        XCTAssertNotEqual(listening, done, "识别与结果配色应不同")
    }

    // MARK: - 音频弹簧（velocity-aware 呼吸）

    func testSpringConvergesToTarget() {
        var pos = 0.0, vel = 0.0
        // 60 帧 @ ~30fps 追踪恒定目标 0.8，应收敛到目标附近
        for _ in 0..<60 {
            let s = AtmosphereTransition.springStep(position: pos, velocity: vel, target: 0.8, dt: 1.0 / 30.0)
            pos = s.position; vel = s.velocity
        }
        XCTAssertEqual(pos, 0.8, accuracy: 0.02, "弹簧应收敛到目标电平")
        XCTAssertEqual(vel, 0, accuracy: 0.1, "收敛后速度趋近 0")
    }

    func testSpringInheritsVelocityNotInstant() {
        // 单帧不应瞬达目标（区别于「直接赋值」），体现惯性
        let s = AtmosphereTransition.springStep(position: 0, velocity: 0, target: 1, dt: 1.0 / 30.0)
        XCTAssertGreaterThan(s.position, 0, "应开始朝目标移动")
        XCTAssertLessThan(s.position, 0.2, "但不瞬达——有惯性")
        XCTAssertGreaterThan(s.velocity, 0, "获得朝目标的速度")
    }

    func testSpringClampsLargeDtNoExplosion() {
        // 掉帧/切后台回来 dt 很大时，内部夹 dt 防显式积分发散
        let s = AtmosphereTransition.springStep(position: 0, velocity: 0, target: 1, dt: 5.0)
        XCTAssertTrue(s.position.isFinite && s.velocity.isFinite, "大 dt 不应发散为 NaN/Inf")
        XCTAssertLessThan(s.position, 1.5, "大 dt 单步仍受控")
    }

    func testSpringZeroDtIsNoOp() {
        let s = AtmosphereTransition.springStep(position: 0.5, velocity: 0.3, target: 1, dt: 0)
        XCTAssertEqual(s.position, 0.5, accuracy: 0.0001)
        XCTAssertEqual(s.velocity, 0.3, accuracy: 0.0001)
    }

    func testSpringDecaysBackToZeroWhenTargetZero() {
        var pos = 0.9, vel = 0.0
        for _ in 0..<90 {
            let s = AtmosphereTransition.springStep(position: pos, velocity: vel, target: 0, dt: 1.0 / 30.0)
            pos = s.position; vel = s.velocity
        }
        XCTAssertEqual(pos, 0, accuracy: 0.02, "目标归零时应柔和衰减回落（离开录音）")
    }
}
