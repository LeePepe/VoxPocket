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
                XCTAssertNotEqual(colors[index], colors[other])
            }
        }
    }

    func testIslandStatusAndWashUseMainUIColorsExactly() {
        for status in RecorderStatus.allCases {
            let mainColors = AtmosphereGlass.colors(for: status)
            XCTAssertEqual(QuickRecordingColors.atmosphere(status), [mainColors[0], mainColors[4], mainColors[1]])
            if status != .idle { XCTAssertEqual(QuickRecordingColors.status(status), mainColors[0]) }
        }
    }

    func testMainUIStageHueOrderIsPreserved() {
        let recording = components(QuickRecordingColors.status(.listening))
        let transcription = components(QuickRecordingColors.status(.transcribing))
        let refinement = components(QuickRecordingColors.status(.refining))
        XCTAssertGreaterThan(recording[1], recording[2])
        XCTAssertGreaterThan(transcription[2], transcription[1])
        XCTAssertGreaterThan(refinement[0], transcription[0])
    }

    func testAudioEnergyIsBoundedAndOnlyAffectsRecording() {
        XCTAssertEqual(QuickRecordingColors.energy(status: .listening, audioLevel: -2), 0)
        XCTAssertEqual(QuickRecordingColors.energy(status: .listening, audioLevel: 2), 1)
        XCTAssertEqual(QuickRecordingColors.energy(status: .listening, audioLevel: .nan), 0)
        XCTAssertEqual(QuickRecordingColors.energy(status: .listening, audioLevel: .infinity), 0)
        XCTAssertEqual(QuickRecordingColors.energy(status: .refining, audioLevel: 0.8), 0)
    }

    func testAccessibilityCanDisableDecorativeColorWash() {
        XCTAssertTrue(QuickRecordingColors.allowsAtmosphere(reduceTransparency: false, increasedContrast: false))
        XCTAssertFalse(QuickRecordingColors.allowsAtmosphere(reduceTransparency: true, increasedContrast: false))
        XCTAssertFalse(QuickRecordingColors.allowsAtmosphere(reduceTransparency: false, increasedContrast: true))
    }

    func testWhiteTranscriptRemainsReadableAtMaximumWashIntensity() {
        let background = components(QuickRecordingColors.neutrals.card)
        let foreground = components(QuickRecordingColors.neutrals.text1)
        for status in RecorderStatus.allCases {
            let colors = QuickRecordingColors.atmosphere(status).map(components)
            let leading = QuickRecordingColors.leadingWashOpacity
            let trailing = QuickRecordingColors.trailingWashOpacity
            let ribbon = QuickRecordingColors.baseRibbonOpacity + QuickRecordingColors.audioRibbonBoost
            let first = zip(colors[0], background).map { $0 * leading + $1 * (1 - leading) }
            let second = zip(colors[2], first).map { $0 * trailing + $1 * (1 - trailing) }
            for color in colors {
                let composed = zip(color, second).map { $0 * ribbon + $1 * (1 - ribbon) }
                XCTAssertGreaterThanOrEqual(contrast(foreground, composed), 4.5)
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
