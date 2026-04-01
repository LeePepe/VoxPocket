// VoxViewInspector.swift
// VoxPocket UI 元素检查辅助工具
// 提供针对 VoxPocket 关键 UI 元素的 accessibility identifier 常量
// 以及基于 XCTest / AX API 的 UI 状态断言辅助

import SwiftUI
#if canImport(XCTest)
import XCTest
#endif

// MARK: - VoxPocket Accessibility Identifiers

/// VoxPocket 视图中所有 accessibility identifier 常量
///
/// 视图层须通过 `.accessibilityIdentifier(VoxAccessibilityID.xxx)` 标注
/// XCUITest 和 VoxViewQuery 均使用这些常量定位元素
public enum VoxAccessibilityID {
    // 录音控制
    public static let recordButton       = "vox.record.button"
    public static let stopButton         = "vox.stop.button"
    public static let recordingIndicator = "vox.recording.indicator"

    // 转录文本
    public static let liveTranscriptText  = "vox.transcript.live"
    public static let finalTranscriptText = "vox.transcript.final"

    // 润色
    public static let refineButton        = "vox.refine.button"
    public static let refinedText         = "vox.refined.text"
    public static let refinementProgress  = "vox.refinement.progress"

    // 会话列表
    public static let sessionList         = "vox.session.list"
    public static let sessionListItem     = "vox.session.list.item"

    // 快速录音面板
    public static let quickRecordPanel    = "vox.quick.panel"
    public static let quickRecordStatus   = "vox.quick.status"
}

// MARK: - VoxViewQuery（XCUITest 封装）
// 仅在 XCTest 可用时（Xcode UITest target）编译

#if canImport(XCTest)
/// 基于 XCUITest 的 VoxPocket 视图状态查询工具
///
/// 在 UI 测试 target（XCUITest）中使用，通过 accessibility identifier 定位元素。
///
/// 使用示例：
/// ```swift
/// let query = VoxViewQuery(app: XCUIApplication())
/// XCTAssertTrue(query.recordButton.exists)
/// XCTAssertFalse(query.recordingIndicator.exists)
/// ```
public struct VoxViewQuery {
    private let app: XCUIApplication

    public init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: 录音控制

    /// 录音按钮元素
    public var recordButton: XCUIElement {
        app.buttons[VoxAccessibilityID.recordButton]
    }

    /// 停止录音按钮元素
    public var stopButton: XCUIElement {
        app.buttons[VoxAccessibilityID.stopButton]
    }

    /// 录音进行中指示器（可为任意元素类型）
    public var recordingIndicator: XCUIElement {
        app.otherElements[VoxAccessibilityID.recordingIndicator]
    }

    // MARK: 转录文本

    /// 实时转录文本元素
    public var liveTranscriptText: XCUIElement {
        app.staticTexts[VoxAccessibilityID.liveTranscriptText]
    }

    /// 最终转录文本元素
    public var finalTranscriptText: XCUIElement {
        app.staticTexts[VoxAccessibilityID.finalTranscriptText]
    }

    // MARK: 润色

    /// 润色按钮
    public var refineButton: XCUIElement {
        app.buttons[VoxAccessibilityID.refineButton]
    }

    /// 润色结果文本
    public var refinedText: XCUIElement {
        app.staticTexts[VoxAccessibilityID.refinedText]
    }

    /// 润色进度指示器
    public var refinementProgress: XCUIElement {
        app.activityIndicators[VoxAccessibilityID.refinementProgress]
    }

    // MARK: 会话列表

    /// 会话列表容器
    public var sessionList: XCUIElement {
        app.collectionViews[VoxAccessibilityID.sessionList]
    }

    /// 所有会话列表条目
    public var sessionListItems: XCUIElementQuery {
        app.cells.matching(identifier: VoxAccessibilityID.sessionListItem)
    }

    /// 会话条目数量
    public var sessionCount: Int {
        sessionListItems.count
    }

    // MARK: 快速录音面板

    /// 快速录音浮动面板容器
    public var quickRecordPanel: XCUIElement {
        app.otherElements[VoxAccessibilityID.quickRecordPanel]
    }

    /// 快速录音状态文本
    public var quickRecordStatus: XCUIElement {
        app.staticTexts[VoxAccessibilityID.quickRecordStatus]
    }

    // MARK: 等待辅助

    /// 等待元素出现（最多 `timeout` 秒）
    @discardableResult
    public func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// 等待录音按钮出现
    @discardableResult
    public func waitForRecordButton(timeout: TimeInterval = 5.0) -> Bool {
        waitFor(recordButton, timeout: timeout)
    }

    /// 等待转录文本出现
    @discardableResult
    public func waitForTranscript(timeout: TimeInterval = 15.0) -> Bool {
        waitFor(finalTranscriptText, timeout: timeout)
            || waitFor(liveTranscriptText, timeout: 1.0)
    }
}

// MARK: - XCTestCase 断言扩展

extension XCTestCase {

    /// 断言录音按钮存在
    public func assertRecordButtonExists(
        in query: VoxViewQuery,
        timeout: TimeInterval = 5.0,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            query.waitForRecordButton(timeout: timeout),
            "录音按钮在 \(timeout) 秒内未出现",
            file: file,
            line: line
        )
    }

    /// 断言不处于录音状态（录音指示器不存在）
    public func assertNotRecording(
        in query: VoxViewQuery,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            query.recordingIndicator.exists,
            "预期无录音指示器，但元素存在",
            file: file,
            line: line
        )
    }

    /// 断言转录文本已出现
    public func assertTranscriptVisible(
        in query: VoxViewQuery,
        timeout: TimeInterval = 15.0,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let appeared = query.waitForTranscript(timeout: timeout)
        XCTAssertTrue(appeared, "转录文本在 \(timeout) 秒内未出现", file: file, line: line)
    }
}
#endif // canImport(XCTest)

// MARK: - SwiftUI Modifier：注入 Accessibility Identifiers

extension View {
    /// 便捷修饰器：以 `VoxAccessibilityID` 常量标注 accessibility identifier
    public func voxAccessibilityID(_ id: String) -> some View {
        self.accessibilityIdentifier(id)
    }
}
