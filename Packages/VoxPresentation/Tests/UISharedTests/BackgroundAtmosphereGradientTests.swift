import XCTest
@testable import UIShared

final class BackgroundAtmosphereGradientTests: XCTestCase {
    /// less is more：每个阶段现在只保留单层方向光晕（原本 2–3 层 .screen 叠加已砍除）。
    func testEachStageHasExactlyOneDirectionalGradient() {
        for status in RecorderStatus.allCases {
            let gradients = AtmosphereGradientPresets.directions(for: status, modulation: 0.5)
            XCTAssertEqual(gradients.count, 1, "\(status) 应只有一层方向渐变（砍叠层后）")
        }
    }

    /// 各阶段保留了各自代表性的方向与色，仍彼此可区分（颜色语言不被削弱）。
    func testStagesRemainVisuallyDistinct() {
        let idle = AtmosphereGradientPresets.directions(for: .idle, modulation: 0).first
        let listening = AtmosphereGradientPresets.directions(for: .listening, modulation: 0).first
        let refining = AtmosphereGradientPresets.directions(for: .refining, modulation: 0).first

        XCTAssertNotNil(idle)
        XCTAssertNotNil(listening)
        XCTAssertNotNil(refining)
        // listening 用横向光（leading→trailing），refining 用纵向光（top→bottom），方向不同
        XCTAssertEqual(listening?.start, .leading)
        XCTAssertEqual(refining?.start, .top)
    }

    /// modulation（音频/脉动能量）仍线性抬升该层不透明度。
    func testModulationRaisesOpacity() {
        let low = AtmosphereGradientPresets.directions(for: .listening, modulation: 0).first!
        let high = AtmosphereGradientPresets.directions(for: .listening, modulation: 1).first!
        XCTAssertGreaterThan(high.opacity, low.opacity)
    }
}
