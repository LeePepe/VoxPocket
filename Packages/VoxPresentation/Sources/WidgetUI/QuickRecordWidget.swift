import AppIntents
import SwiftUI
import WidgetKit

/// 简单时间线提供者（静态 Widget，无需动态数据）
struct QuickRecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordEntry {
        QuickRecordEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        completion(QuickRecordEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        let entry = QuickRecordEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

/// Widget 时间线条目
struct QuickRecordEntry: TimelineEntry {
    let date: Date
}

/// 快速录音 Widget
///
/// 主屏幕与锁屏小组件：通过 `AudioRecordingIntent` 在后台一键启动/停止语音录入并弹出灵动岛，无需直接进入 App。
public struct QuickRecordWidget: Widget {
    public let kind = "com.tianpli.VoxPocket.QuickRecord"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { _ in
            QuickRecordWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("快速录音")
        .description("后台一键开启或停止录音，配合灵动岛实时显示")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall])
        #endif
    }
}

/// 快速录音 Widget 视图
struct QuickRecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        #if os(iOS)
        Button(intent: ToggleQuickCaptureIntent()) {
            widgetLabel
        }
        .buttonStyle(.plain)
        #else
        Link(destination: URL(string: "voxpocket://quickRecord")!) {
            widgetLabel
        }
        #endif
    }

    @ViewBuilder
    private var widgetLabel: some View {
        #if os(iOS)
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform.and.mic")
                    .font(.headline)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.circle.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VoxPocket 录音")
                        .font(.headline)
                    Text("点按启停 · 灵动岛反馈")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            smallSystemWidgetContent
        }
        #else
        smallSystemWidgetContent
        #endif
    }

    private var smallSystemWidgetContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.orange)

            Text("点按启停录音")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("灵动岛后台录入")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview(as: .systemSmall) {
    QuickRecordWidget()
} timeline: {
    QuickRecordEntry(date: Date())
}
