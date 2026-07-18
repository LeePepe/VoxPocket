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

    // MARK: - 入场「呼吸」（less is more：柔光为主，不缩放）

    func testActiveStagesBreatheWithGlowNoScale() {
        for status in [RecorderStatus.listening, .transcribing, .refining] {
            let start = AtmosphereTransition.dynamics(status: status, transitionElapsed: 0)
            let peak = AtmosphereTransition.dynamics(status: status, transitionElapsed: 0.5)
            let settled = AtmosphereTransition.dynamics(status: status, transitionElapsed: 1.0)

            XCTAssertEqual(start.scale, 1, accuracy: 0.0001, "\(status) 不缩放")
            XCTAssertEqual(peak.scale, 1, accuracy: 0.0001, "\(status) 全程不缩放（去膨胀）")
            XCTAssertEqual(start.bloom, 0, accuracy: 0.001, "\(status) 起点无柔光")
            XCTAssertGreaterThan(peak.bloom, 0.15, "\(status) 中途有明显但克制的柔光")
            XCTAssertLessThan(settled.bloom, 0.02, "\(status) 柔光消散")
        }
    }

    func testBreathGlowIsRestrained() {
        // less is more：柔光峰值应克制，不超过 0.26
        let peak = AtmosphereTransition.dynamics(status: .listening, transitionElapsed: 0.5)
        XCTAssertLessThanOrEqual(peak.bloom, 0.26)
    }

    // MARK: - 完成「安定内收」（极轻微）

    func testDoneSettlesInward() {
        let entry = AtmosphereTransition.dynamics(status: .done, transitionElapsed: 0)
        let settled = AtmosphereTransition.dynamics(status: .done, transitionElapsed: 0.9)

        XCTAssertGreaterThan(entry.scale, 1, "结果入场时极轻微放大")
        XCTAssertLessThanOrEqual(entry.scale, 1.02, "但收敛克制，不超过 2%")
        XCTAssertGreaterThan(entry.bloom, 0.15, "结果入场时柔光升起")
        XCTAssertEqual(settled.scale, 1, accuracy: 0.001, "收拢到静止（安定）")
        XCTAssertLessThan(settled.bloom, 0.02, "柔光沉降")
    }

    func testDoneScaleIsMonotonicDecreasing() {
        var last = CGFloat.greatestFiniteMagnitude
        for i in 0...10 {
            let te = Double(i) / 10 * 0.9
            let s = AtmosphereTransition.dynamics(status: .done, transitionElapsed: te).scale
            XCTAssertLessThanOrEqual(s, last + 0.0001, "结果内收应单调收拢，不回弹")
            last = s
        }
    }

    // MARK: - 静止阶段

    func testIdleAndErrorAreStatic() {
        for status in [RecorderStatus.idle, .error] {
            for te in [0.0, 0.4, 0.9] {
                let d = AtmosphereTransition.dynamics(status: status, transitionElapsed: te)
                XCTAssertEqual(d.scale, 1, accuracy: 0.0001, "\(status) 无入场膨胀")
                XCTAssertEqual(d.bloom, 0, accuracy: 0.0001, "\(status) 无光晕")
            }
        }
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
