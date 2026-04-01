// VoxFunctionalTestTests.swift
// VoxFunctionalTest 模块的单元测试
// 测试辅助工具本身的正确性（不依赖运行中的应用）

import XCTest
import SwiftUI
@testable import VoxFunctionalTest

// MARK: - 快照配置测试

final class VoxSnapshotConfigTests: XCTestCase {

    // MARK: 设备预设尺寸

    func testIPhoneProDefaultSize() {
        XCTAssertEqual(VoxSnapshotDevice.iPhoneProDefault.size.width, 393)
        XCTAssertEqual(VoxSnapshotDevice.iPhoneProDefault.size.height, 852)
    }

    func testMacQuickRecordingPanelSize() {
        XCTAssertEqual(VoxSnapshotDevice.macQuickRecordingPanel.size.width, 480)
        XCTAssertEqual(VoxSnapshotDevice.macQuickRecordingPanel.size.height, 280)
    }

    func testMacEditorWindowSize() {
        XCTAssertEqual(VoxSnapshotDevice.macEditorWindow.size.width, 900)
        XCTAssertEqual(VoxSnapshotDevice.macEditorWindow.size.height, 700)
    }

    // MARK: 设备名称

    func testDeviceNames() {
        XCTAssertEqual(VoxSnapshotDevice.iPhoneProDefault.name, "iPhone15Pro")
        XCTAssertEqual(VoxSnapshotDevice.macQuickRecordingPanel.name, "Mac_QuickPanel")
        XCTAssertEqual(VoxSnapshotDevice.macEditorWindow.name, "Mac_Editor")
    }

    // MARK: 配置预设

    func testIPhoneLightPreset() {
        let config = VoxSnapshotConfig.iPhoneLight
        XCTAssertEqual(config.colorScheme, .light)
        XCTAssertEqual(config.device.name, "iPhone15Pro")
        XCTAssertFalse(config.record)
    }

    func testIPhoneDarkPreset() {
        let config = VoxSnapshotConfig.iPhoneDark
        XCTAssertEqual(config.colorScheme, .dark)
        XCTAssertEqual(config.device.name, "iPhone15Pro")
    }

    func testMacEditorLightPreset() {
        let config = VoxSnapshotConfig.macEditorLight
        XCTAssertEqual(config.colorScheme, .light)
        XCTAssertEqual(config.device.name, "Mac_Editor")
    }

    func testDefaultPrecisionIsExact() {
        // 默认精度 1.0 = 精确像素匹配
        let config = VoxSnapshotConfig()
        XCTAssertEqual(config.precision, 1.0)
    }

    func testCustomPrecision() {
        let config = VoxSnapshotConfig(precision: 0.95)
        XCTAssertEqual(config.precision, 0.95, accuracy: 0.001)
    }
}

// MARK: - 性能监控测试

final class VoxPerformanceMonitorTests: XCTestCase {

    // MARK: 阈值断言

    func testWithinThresholdPasses() {
        // 不应触发 XCTFail
        VoxPerformanceMonitor.assertWithinThreshold(
            duration: 0.5,
            threshold: 1.0,
            operation: .startRecording
        )
    }

    func testOperationRawValues() {
        XCTAssertEqual(VoxOperation.startRecording.rawValue, "StartRecording")
        XCTAssertEqual(VoxOperation.stopRecording.rawValue, "StopRecording")
        XCTAssertEqual(VoxOperation.firstTranscript.rawValue, "FirstTranscript")
        XCTAssertEqual(VoxOperation.firstRefinement.rawValue, "FirstRefinement")
        XCTAssertEqual(VoxOperation.sessionListLoad.rawValue, "SessionListLoad")
    }

    // MARK: 帧率追踪器统计

    func testFrameTrackerInitialState() {
        let tracker = VoxFrameTracker()
        XCTAssertEqual(tracker.averageFPS, 0)
        XCTAssertEqual(tracker.minimumFPS, 0)
        XCTAssertEqual(tracker.droppedFrameCount, 0)
    }

    func testMeasureReturnsReasonableValue() async throws {
        let duration = try await VoxPerformanceMonitor.measure(
            operation: .sessionListLoad,
            iterations: 3
        ) {
            // 模拟轻量操作：约 10ms
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // 每次 ~10ms，3 次平均应在 5ms–500ms 范围内
        XCTAssertGreaterThan(duration, 0.005)
        XCTAssertLessThan(duration, 0.5)
    }
}

// MARK: - 快照断言集成测试（需要 UI 环境）
// 以下测试演示如何使用 VoxSnapshotTesting，实际运行需要快照参考文件

final class VoxSnapshotIntegrationExamples: XCTestCase {

    /// 示例：对一个简单 SwiftUI 视图运行快照断言
    /// 注意：首次运行时设置 `record: true` 生成参考文件，之后改为 false 进行断言
    @MainActor
    func testSimpleViewSnapshot_Example() throws {
        // 跳过：演示用例，需要参考快照文件存在
        try XCTSkipIf(true, "快照集成测试需在首次运行时设置 record=true 生成参考文件")

        let view = Text("VoxPocket 录音中…")
            .font(.title)
            .foregroundColor(.red)

        VoxSnapshotTesting.assert(
            view: view,
            config: .iPhoneLight,
            snapshotName: "RecordingIndicatorText_Example"
        )
    }

    /// 示例：在明暗模式下批量对比
    @MainActor
    func testDarkAndLightSnapshot_Example() throws {
        try XCTSkipIf(true, "快照集成测试需在首次运行时设置 record=true 生成参考文件")

        let view = RoundedRectangle(cornerRadius: 12)
            .fill(Color.accentColor)
            .frame(width: 64, height: 64)

        VoxSnapshotTesting.assertMultiple(
            view: view,
            configs: [.iPhoneLight, .iPhoneDark],
            snapshotName: "AccentButton"
        )
    }
}

// MARK: - Accessibility ID 常量测试

final class VoxAccessibilityIDTests: XCTestCase {

    func testAllIDsAreNonEmpty() {
        let ids = [
            VoxAccessibilityID.recordButton,
            VoxAccessibilityID.stopButton,
            VoxAccessibilityID.recordingIndicator,
            VoxAccessibilityID.liveTranscriptText,
            VoxAccessibilityID.finalTranscriptText,
            VoxAccessibilityID.refineButton,
            VoxAccessibilityID.refinedText,
            VoxAccessibilityID.refinementProgress,
            VoxAccessibilityID.sessionList,
            VoxAccessibilityID.sessionListItem,
            VoxAccessibilityID.quickRecordPanel,
            VoxAccessibilityID.quickRecordStatus,
        ]
        for id in ids {
            XCTAssertFalse(id.isEmpty, "accessibility ID 不应为空: \(id)")
            XCTAssertTrue(id.hasPrefix("vox."), "所有 ID 应以 'vox.' 开头: \(id)")
        }
    }

    func testIDsAreUnique() {
        let ids = [
            VoxAccessibilityID.recordButton,
            VoxAccessibilityID.stopButton,
            VoxAccessibilityID.recordingIndicator,
            VoxAccessibilityID.liveTranscriptText,
            VoxAccessibilityID.finalTranscriptText,
            VoxAccessibilityID.refineButton,
            VoxAccessibilityID.refinedText,
            VoxAccessibilityID.refinementProgress,
            VoxAccessibilityID.sessionList,
            VoxAccessibilityID.sessionListItem,
            VoxAccessibilityID.quickRecordPanel,
            VoxAccessibilityID.quickRecordStatus,
        ]
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "所有 accessibility ID 必须唯一")
    }
}
