import XCTest
@testable import UIShared

final class BackgroundAtmosphereGradientTests: XCTestCase {
    func testIdleUsesMultipleDirectionalGradients() {
        let gradients = AtmosphereGradientPresets.directions(for: .idle, modulation: 0)

        XCTAssertGreaterThanOrEqual(gradients.count, 2)
        XCTAssertTrue(
            gradients.contains { $0.start == .topLeading && $0.end == .bottomTrailing }
        )
        XCTAssertTrue(
            gradients.contains { $0.start == .bottomLeading && $0.end == .topTrailing }
        )
    }

    func testListeningUsesDifferentDirections() {
        let gradients = AtmosphereGradientPresets.directions(for: .listening, modulation: 0.7)
        let uniqueDirections = Set(gradients.map { "\($0.start.rawValue)->\($0.end.rawValue)" })

        XCTAssertGreaterThanOrEqual(uniqueDirections.count, 2)
    }
}
