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

    // MARK: - 入场「呼吸」（吸气）

    func testActiveStagesInhaleThenReturn() {
        for status in [RecorderStatus.listening, .transcribing, .refining] {
            let start = AtmosphereTransition.dynamics(status: status, transitionElapsed: 0)
            let peak = AtmosphereTransition.dynamics(status: status, transitionElapsed: 0.45)
            let settled = AtmosphereTransition.dynamics(status: status, transitionElapsed: 0.9)

            XCTAssertEqual(start.scale, 1, accuracy: 0.001, "\(status) 起点应静止")
            XCTAssertGreaterThan(peak.scale, start.scale, "\(status) 中途应膨胀（吸气）")
            XCTAssertGreaterThan(peak.bloom, 0.3, "\(status) 峰值应有明显光晕")
            XCTAssertEqual(settled.scale, 1, accuracy: 0.001, "\(status) 呼吸结束回到静止")
            XCTAssertLessThan(settled.bloom, 0.02, "\(status) 光晕消散")
        }
    }

    func testInhaleScaleIsSubtle() {
        // 「更大胆」但不失控：整层缩放峰值不应超过 2%
        let peak = AtmosphereTransition.dynamics(status: .listening, transitionElapsed: 0.45)
        XCTAssertLessThan(peak.scale, 1.02)
    }

    // MARK: - 完成「安定内收」

    func testDoneSettlesInward() {
        let entry = AtmosphereTransition.dynamics(status: .done, transitionElapsed: 0)
        let settled = AtmosphereTransition.dynamics(status: .done, transitionElapsed: 0.85)

        XCTAssertGreaterThan(entry.scale, 1, "结果入场时轻微放大")
        XCTAssertGreaterThan(entry.bloom, 0.3, "结果入场时光晕升起")
        XCTAssertEqual(settled.scale, 1, accuracy: 0.001, "收拢到静止（安定）")
        XCTAssertLessThan(settled.bloom, 0.02, "光晕沉降")
    }

    func testDoneScaleIsMonotonicDecreasing() {
        var last = CGFloat.greatestFiniteMagnitude
        for i in 0...10 {
            let te = Double(i) / 10 * 0.85
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
}
