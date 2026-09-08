#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import UIShared

final class QuickRecordingColorsTests: XCTestCase {
    func testActiveStagesHaveDistinctVisibleStatusColors() {
        let colors = [RecorderStatus.listening, .transcribing, .refining, .done, .error].map {
            components(QuickRecordingColors.status($0))
        }
        let background = components(QuickRecordingColors.neutrals.card)
        for index in colors.indices {
            XCTAssertGreaterThanOrEqual(contrast(colors[index], background), 3)
            for other in colors.indices where other > index {
                XCTAssertGreaterThan(zip(colors[index], colors[other]).map { abs($0 - $1) }.reduce(0, +), 0.15)
            }
        }
    }
    func testTranscriptAndErrorLabelMeetSmallTextContrast() {
        let background = components(QuickRecordingColors.neutrals.card)
        let red = components(QuickRecordingColors.danger)
        let errorBackground = zip(red, background).map { $0 * 0.13 + $1 * 0.87 }
        XCTAssertGreaterThanOrEqual(contrast(components(QuickRecordingColors.neutrals.text1), errorBackground), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(components(QuickRecordingColors.neutrals.text2), background), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(components(QuickRecordingColors.primary.primaryText), background), 4.5)
    }

    private func components(_ color: Color) -> [Double] {
        let resolved = NSColor(color).usingColorSpace(.sRGB)!
        return [Double(resolved.redComponent), Double(resolved.greenComponent), Double(resolved.blueComponent)]
    }

    private func contrast(_ foreground: [Double], _ background: [Double]) -> Double {
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
#endif
