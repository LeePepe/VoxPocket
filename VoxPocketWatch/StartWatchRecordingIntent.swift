import AppIntents

struct StartWatchRecordingIntent: AppIntent, AudioRecordingIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "开始录音"
    static var description = IntentDescription("打开 VoxPocket Watch 录音器并开始录音")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRecordingRuntime.start()
        return .result()
    }
}

struct VoxPocketWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWatchRecordingIntent(), phrases: ["用 \(.applicationName) 录音"], shortTitle: "开始录音", systemImageName: "waveform.and.mic")
    }
}
