import SwiftUI
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import AppIntents
import WidgetKit

public struct VoxCaptureActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var mode: String
        public var elapsedSeconds: Int
        public var isRecording: Bool
        public init(mode: String, elapsedSeconds: Int = 0, isRecording: Bool = true) {
            self.mode = mode
            self.elapsedSeconds = elapsedSeconds
            self.isRecording = isRecording
        }
    }
    public var sessionID: String
    public init(sessionID: String) { self.sessionID = sessionID }
}

@available(iOS 16.1, *)
public struct VoxCaptureLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoxCaptureActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.isRecording ? "waveform.circle.fill" : "sparkles")
                    .font(.title2)
                    .foregroundStyle(context.state.isRecording ? .red : .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.mode)
                        .font(.subheadline.weight(.semibold))
                    Text(Self.elapsed(context.state.elapsedSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button(intent: FinishCaptureIntent()) {
                    Label("完成录音", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel("完成录音")
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.84))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.mode, systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Self.elapsed(context.state.elapsedSeconds))
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("操作按钮一键启停", systemImage: "button.vertical.left.press")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(intent: FinishCaptureIntent()) {
                            Label("完成录音", systemImage: "stop.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(Self.elapsed(context.state.elapsedSeconds))
                    .font(.caption2.monospacedDigit())
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            }
        }
    }

    public static let stopRecordingURL = URL(string: "voxpocket://stopRecording")!
    private static func elapsed(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

@available(iOS 18.0, *)
public struct ToggleQuickCaptureIntent: AudioRecordingIntent {
    public static let title: LocalizedStringResource = "快速录音 / 停止"
    public static let description = IntentDescription("无需打开 App，在后台启动或停止语音录入并联动灵动岛")
    public static let openAppWhenRun: Bool = false
    public static let didRequestToggleNotification = Notification.Name("vox.liveActivity.toggleCapture")
    @MainActor public static var performHandler: (() async -> Void)?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let handler = Self.performHandler {
            await handler()
        } else {
            NotificationCenter.default.post(name: Self.didRequestToggleNotification, object: nil)
        }
        return .result()
    }
}

@available(iOS 18.0, *)
public struct FinishCaptureIntent: AudioRecordingIntent {
    public static let title: LocalizedStringResource = "完成录音"
    public static let description = IntentDescription("停止当前后台语音录入并保存结果")
    public static let openAppWhenRun: Bool = false
    public static let didRequestFinishNotification = Notification.Name("vox.liveActivity.finishCapture")
    @MainActor public static var performHandler: (() async -> Void)?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let handler = Self.performHandler {
            await handler()
        } else {
            NotificationCenter.default.post(name: Self.didRequestFinishNotification, object: nil)
        }
        return .result()
    }
}
#endif
