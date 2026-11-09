import AppIntents
import CoreModels
import Preferences
import UseCases
#if os(iOS)
import WidgetUI
#endif

/// 快速录音 / 停止 Intent（AudioRecordingIntent）
///
/// 供 Shortcuts app、iPhone Action Button（操作按钮）、桌面/锁屏 Widget 与 Control Center 控件使用。
/// 采用 `AudioRecordingIntent` 且 `openAppWhenRun = false`，无需跳进主 App 即可在后台启动/停止语音录入，
/// 并自动联动灵动岛（Dynamic Island）实时显示声波与计时：
/// - 未在录音时按下：按设置中的去向（直接存入待办 / 自动复制到剪贴板）在后台启动录音并弹出灵动岛；
/// - 正在录音时再次按下：立即结束录音，自动提炼存入待办或写入系统剪贴板。
#if os(iOS)
struct StartRecordingIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "开始或停止录音"
    static var description = IntentDescription("无需打开 VoxPocket，在后台一键开始或停止语音录入并联动灵动岛")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await LLMAppConfig.loadRuntimeConfiguration()
        await ServiceContainer.shared.toggleQuickCaptureFromIntent()
        return .result()
    }
}
#else
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "开始录音"
    static var description = IntentDescription("启动 VoxPocket 并按设置去向开始语音录入")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try await LLMAppConfig.loadRuntimeConfiguration()
        ServiceContainer.shared.deepLinkRouter.pendingAction = .startRecording
        return .result()
    }
}
#endif

/// App Shortcuts 注册
///
/// 让 Shortcuts app 与 iPhone Action Button 自动发现 VoxPocket 提供的快捷操作。
struct VoxPocketShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "用 \(.applicationName) 录音",
                "开始 \(.applicationName) 录音",
                "用 \(.applicationName) 记待办",
            ],
            shortTitle: "开始或停止录音",
            systemImageName: "waveform.and.mic"
        )
    }
}
