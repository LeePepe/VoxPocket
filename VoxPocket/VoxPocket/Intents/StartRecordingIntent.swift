import AppIntents
import UseCases

/// 开始录音 Intent
///
/// 供 Shortcuts app、Action Button、Control Center 控件使用。
/// 执行时启动 app 并自动开始语音识别。
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "开始录音"
    static var description = IntentDescription("启动 VoxPocket 并开始语音识别")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ServiceContainer.shared.deepLinkRouter.pendingAction = .startRecording
        return .result()
    }
}

/// App Shortcuts 注册
///
/// 让 Shortcuts app 自动发现 VoxPocket 提供的快捷操作。
struct VoxPocketShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "用 \(.applicationName) 录音",
                "开始 \(.applicationName) 录音",
            ],
            shortTitle: "录音",
            systemImageName: "mic.fill"
        )
    }
}
