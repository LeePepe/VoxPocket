//
//  ServiceContainer.swift
//  VoxPocket
//
//  依赖注入容器，管理所有共享服务和用例实例
//

#if os(macOS)
import Foundation
import SwiftUI
import Combine
import TranscriptionKit
import LLMKit
import UseCases
import PlatformAdapters
import UIShared
import PlatformUI

/// 服务容器
///
/// 集中管理所有服务和用例实例，避免重复创建。
/// 提供工厂方法创建 ViewModel。
@MainActor
public final class ServiceContainer: ObservableObject {

    // MARK: - 单例

    public static let shared = ServiceContainer()

    // MARK: - 基础服务

    public let transcriber: AppleSpeechTranscriber
    public let llmService: DefaultLLMService
    public let clipboardService: MacOSClipboardService
    public let accessibilityService: MacOSAccessibilityService
    public let hotkeyService: MacOSGlobalHotkeyService

    // MARK: - Use Cases

    public let editingUseCase: DefaultEditingUseCase
    public let recordingUseCase: DefaultRecordingUseCase
    public let transcriptionUseCase: DefaultTranscriptionUseCase
    public let historyUseCase: DefaultHistoryUseCase
    public let refinementUseCase: DefaultRefinementUseCase

    // MARK: - 状态跟踪

    /// 当前是否有录音正在进行
    @Published public var isRecordingActive: Bool = false

    /// 活动的录音源标识
    @Published public var activeRecordingSource: RecordingSource? = nil

    // MARK: - 初始化

    private init() {
        // 初始化基础服务
        transcriber = AppleSpeechTranscriber()
        llmService = DefaultLLMService()
        clipboardService = MacOSClipboardService.shared
        accessibilityService = MacOSAccessibilityService.shared
        hotkeyService = MacOSGlobalHotkeyService.shared

        // 初始化 Use Cases
        editingUseCase = DefaultEditingUseCase()
        recordingUseCase = DefaultRecordingUseCase(coordinator: transcriber)
        transcriptionUseCase = DefaultTranscriptionUseCase(coordinator: transcriber, editing: editingUseCase)
        historyUseCase = DefaultHistoryUseCase(editing: editingUseCase)
        refinementUseCase = DefaultRefinementUseCase(llmService: llmService, editing: editingUseCase)

        print("✅ [ServiceContainer] Initialized")
    }

    // MARK: - ViewModel 工厂方法

    /// 创建完整面板的 EditorViewModel
    public func makeEditorViewModel() -> EditorViewModel {
        EditorViewModel(
            recording: recordingUseCase,
            transcription: transcriptionUseCase,
            editing: editingUseCase,
            history: historyUseCase,
            refinement: refinementUseCase
        )
    }

    /// 创建完整面板的 RootViewModel
    public func makeRootViewModel() -> RootViewModel<MockSessionListViewModel, EditorViewModel> {
        let editor = makeEditorViewModel()
        let sessionList = MockSessionListViewModel()
        return RootViewModel(sessionListState: sessionList, editorState: editor)
    }

    /// 创建快速录音的 ViewModel
    public func makeQuickRecordingViewModel() -> QuickRecordingViewModel {
        QuickRecordingViewModel(
            recordingUseCase: recordingUseCase,
            transcriptionUseCase: transcriptionUseCase,
            refinementUseCase: refinementUseCase,
            clipboardService: clipboardService
        )
    }

    // MARK: - 录音状态管理

    /// 尝试开始录音
    /// - Parameter source: 录音来源
    /// - Returns: 是否成功开始
    public func tryStartRecording(source: RecordingSource) -> Bool {
        guard !isRecordingActive else {
            print("⚠️ [ServiceContainer] Recording already active from: \(activeRecordingSource?.rawValue ?? "unknown")")
            return false
        }

        isRecordingActive = true
        activeRecordingSource = source
        print("🎙️ [ServiceContainer] Recording started from: \(source.rawValue)")
        return true
    }

    /// 结束录音
    public func endRecording() {
        isRecordingActive = false
        activeRecordingSource = nil
        print("⏹️ [ServiceContainer] Recording ended")
    }
}

// MARK: - 录音来源

public enum RecordingSource: String {
    case fullPanel = "FullPanel"
    case quickRecording = "QuickRecording"
    case mainWindow = "MainWindow"
}
#endif
