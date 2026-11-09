import AppIntents
import CoreModels
import Preferences
import UseCases

/// 开始录音 Intent
///
/// 供 Shortcuts app、Action Button、Control Center 控件使用。
/// 执行时启动 app 并按设置的默认去向（直接存入待办 / 自动复制到剪贴板）开始语音识别。
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "开始录音"
    static var description = IntentDescription("启动 VoxPocket 并按设置去向开始语音录入")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try await LLMAppConfig.loadRuntimeConfiguration()
        let preferredMode: CaptureMode? = await UserDefaultsPreferencesStore.shared.getValue(
            for: .iosQuickCaptureDestination
        )
        if let preferredMode {
            ServiceContainer.shared.deepLinkRouter.pendingAction = .startRecordingInMode(preferredMode)
        } else {
            ServiceContainer.shared.deepLinkRouter.pendingAction = .startRecording
        }
        return .result()
    }
}

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
            shortTitle: "开始录音",
            systemImageName: "mic.fill"
        )
    }
}
