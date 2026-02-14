import WidgetKit
import SwiftUI

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
        // 静态 Widget，不需要频繁刷新
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
/// 主屏幕小组件，点击后启动 VoxPocket 并自动开始语音识别。
struct QuickRecordWidget: Widget {
    let kind = "com.tianpli.VoxPocket.QuickRecord"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { _ in
            QuickRecordWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("快速录音")
        .description("点按开始语音识别")
        .supportedFamilies([.systemSmall])
    }
}

/// 快速录音 Widget 视图
struct QuickRecordWidgetView: View {
    var body: some View {
        Link(destination: URL(string: "voxpocket://quickRecord")!) {
            VStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.blue)

                Text("点按录音")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview(as: .systemSmall) {
    QuickRecordWidget()
} timeline: {
    QuickRecordEntry(date: Date())
}
