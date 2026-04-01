// VoxSnapshotTesting.swift
// VoxPocket 视觉回归测试辅助工具
// 封装 swift-snapshot-testing，提供针对 VoxPocket UI 预设配置

import SwiftUI
import SnapshotTesting
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if canImport(XCTest)
import XCTest
#endif

// MARK: - 设备配置预设

/// VoxPocket 快照测试使用的设备/窗口尺寸预设
public enum VoxSnapshotDevice: Sendable {
    /// iPhone 15 Pro (393 × 852 pt)
    case iPhoneProDefault
    /// iPad Pro 13" (1032 × 1376 pt)
    case iPadProDefault
    /// macOS 浮动录音面板 (480 × 280 pt)
    case macQuickRecordingPanel
    /// macOS 主编辑器窗口 (900 × 700 pt)
    case macEditorWindow

    /// 对应的像素尺寸
    public var size: CGSize {
        switch self {
        case .iPhoneProDefault:       return CGSize(width: 393, height: 852)
        case .iPadProDefault:         return CGSize(width: 1032, height: 1376)
        case .macQuickRecordingPanel: return CGSize(width: 480, height: 280)
        case .macEditorWindow:        return CGSize(width: 900, height: 700)
        }
    }

    /// 设备名称（用于快照文件命名）
    public var name: String {
        switch self {
        case .iPhoneProDefault:       return "iPhone15Pro"
        case .iPadProDefault:         return "iPadPro13"
        case .macQuickRecordingPanel: return "Mac_QuickPanel"
        case .macEditorWindow:        return "Mac_Editor"
        }
    }
}

// MARK: - 快照配置

/// 封装单次快照断言所需的全部配置
public struct VoxSnapshotConfig: Sendable {
    /// 目标设备预设
    public let device: VoxSnapshotDevice
    /// 色彩方案（明/暗）
    public let colorScheme: ColorScheme
    /// 允许的像素差异百分比（0.0 – 1.0），默认 0（精确匹配）
    public let precision: Float
    /// 记录模式：`true` 时写入参考快照而非断言
    public let record: Bool

    public init(
        device: VoxSnapshotDevice = .iPhoneProDefault,
        colorScheme: ColorScheme = .light,
        precision: Float = 1.0,
        record: Bool = false
    ) {
        self.device = device
        self.colorScheme = colorScheme
        self.precision = precision
        self.record = record
    }

    // MARK: 常用预设

    /// iPhone 明亮模式
    public static let iPhoneLight = VoxSnapshotConfig(device: .iPhoneProDefault, colorScheme: .light)
    /// iPhone 暗黑模式
    public static let iPhoneDark  = VoxSnapshotConfig(device: .iPhoneProDefault, colorScheme: .dark)
    /// macOS 快速录音面板（明亮）
    public static let macQuickLight = VoxSnapshotConfig(device: .macQuickRecordingPanel, colorScheme: .light)
    /// macOS 快速录音面板（暗黑）
    public static let macQuickDark  = VoxSnapshotConfig(device: .macQuickRecordingPanel, colorScheme: .dark)
    /// macOS 主编辑器（明亮）
    public static let macEditorLight = VoxSnapshotConfig(device: .macEditorWindow, colorScheme: .light)
}

// MARK: - 快照断言入口

/// VoxPocket 快照测试门面
///
/// 使用示例：
/// ```swift
/// VoxSnapshotTesting.assert(
///     view: EditorView(viewModel: fakeVM),
///     config: .iPhoneLight,
///     testName: "EditorView_idle",
///     file: #file, testName: #function, line: #line
/// )
/// ```
public enum VoxSnapshotTesting {

    // MARK: 公共 API（仅在 XCTest 可用时编译）

    #if canImport(XCTest)
    /// 对 SwiftUI 视图执行快照断言
    ///
    /// - Parameters:
    ///   - view:         要截图的 SwiftUI 视图
    ///   - config:       快照配置（设备、色彩方案、精度）
    ///   - snapshotName: 快照文件的唯一名称（省略时使用 `testName`）
    ///   - file:         调用测试文件（用于快照路径计算）
    ///   - testName:     测试函数名
    ///   - line:         行号（断言失败定位用）
    @MainActor
    public static func assert<V: View>(
        view: V,
        config: VoxSnapshotConfig = .iPhoneLight,
        snapshotName: String? = nil,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        let name = snapshotName ?? testName
        let snapshotName = "\(name)_\(config.device.name)_\(config.colorScheme == .dark ? "dark" : "light")"

        #if os(macOS)
        let hostView = makeMacHostView(view: view, config: config)
        assertSnapshot(
            of: hostView,
            as: .image(precision: config.precision, size: config.device.size),
            named: snapshotName,
            record: config.record,
            file: file,
            testName: testName,
            line: line
        )
        #else
        let hostView = makeIOSHostView(view: view, config: config)
        assertSnapshot(
            of: hostView,
            as: .image(precision: config.precision, size: config.device.size),
            named: snapshotName,
            record: config.record,
            file: file,
            testName: testName,
            line: line
        )
        #endif
    }

    /// 对同一视图在多个配置下批量断言
    @MainActor
    public static func assertMultiple<V: View>(
        view: V,
        configs: [VoxSnapshotConfig],
        snapshotName: String,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        for config in configs {
            assert(
                view: view,
                config: config,
                snapshotName: snapshotName,
                file: file,
                testName: testName,
                line: line
            )
        }
    }
    #endif // canImport(XCTest)

    // MARK: 内部辅助（平台视图包装，无需 XCTest）

    #if os(macOS)
    /// 将 SwiftUI 视图包裹为 NSView（macOS）
    @MainActor
    static func makeMacHostView<V: View>(view: V, config: VoxSnapshotConfig) -> NSView {
        let styled = view
            .environment(\.colorScheme, config.colorScheme)
            .frame(width: config.device.size.width, height: config.device.size.height)
        let hosting = NSHostingView(rootView: styled)
        hosting.frame = CGRect(origin: .zero, size: config.device.size)
        return hosting
    }
    #else
    /// 将 SwiftUI 视图包裹为 UIView（iOS）
    @MainActor
    static func makeIOSHostView<V: View>(view: V, config: VoxSnapshotConfig) -> UIView {
        let styled = view
            .environment(\.colorScheme, config.colorScheme)
            .frame(width: config.device.size.width, height: config.device.size.height)
        let vc = UIHostingController(rootView: styled)
        vc.view.frame = CGRect(origin: .zero, size: config.device.size)
        return vc.view
    }
    #endif
}
