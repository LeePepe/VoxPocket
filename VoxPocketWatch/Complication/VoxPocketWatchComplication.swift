import AppIntents
import SwiftUI
import WidgetKit

struct WatchComplicationEntry: TimelineEntry { let date: Date }

struct WatchComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VoxPocketWatchComplication", intent: StartWatchRecordingIntent.self, provider: IntentProvider()) { _ in
            Button(intent: StartWatchRecordingIntent()) {
                Image(systemName: "waveform.and.mic")
            }
            .buttonStyle(.plain)
            .widgetLabel { Text("VoxPocket") }
            .widgetURL(URL(string: "voxpocket-watch://record"))
            .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("VoxPocket 录音")
        .description("打开 VoxPocket Watch 录音器")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

private struct IntentProvider: AppIntentTimelineProvider {
    typealias Entry = WatchComplicationEntry
    typealias Intent = StartWatchRecordingIntent
    func placeholder(in context: Context) -> Entry { WatchComplicationEntry(date: .now) }
    func snapshot(for configuration: Intent, in context: Context) async -> Entry { WatchComplicationEntry(date: .now) }
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> { Timeline(entries: [WatchComplicationEntry(date: .now)], policy: .never) }
    func recommendations() -> [AppIntentRecommendation<Intent>] { [AppIntentRecommendation(intent: StartWatchRecordingIntent(), description: "VoxPocket 录音")] }
}

@main
struct WatchComplicationBundle: WidgetBundle {
    var body: some Widget { WatchComplication() }
}
