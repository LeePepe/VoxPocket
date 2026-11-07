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
        public init(mode: String, elapsedSeconds: Int = 0, isRecording: Bool = true) { self.mode = mode; self.elapsedSeconds = elapsedSeconds; self.isRecording = isRecording }
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
                Image(systemName: "waveform.and.mic").foregroundStyle(.tint)
                VStack(alignment: .leading) { Text(context.state.mode); Text(Self.elapsed(context.state.elapsedSeconds)).monospacedDigit().contentTransition(.numericText()) }
                Spacer()
                Button(intent: FinishCaptureIntent()) { Image(systemName: "checkmark.circle.fill") }.accessibilityLabel("完成录音")
            }.padding().activityBackgroundTint(.black.opacity(0.82))
        } dynamicIsland: { context in
            DynamicIsland { DynamicIslandExpandedRegion(.leading) { Label(context.state.mode, systemImage: "waveform") }; DynamicIslandExpandedRegion(.trailing) { Text(Self.elapsed(context.state.elapsedSeconds)).monospacedDigit() }; DynamicIslandExpandedRegion(.bottom) { Button("完成录音", intent: FinishCaptureIntent()) } } compactLeading: { Image(systemName: "waveform") } compactTrailing: { Text(Self.elapsed(context.state.elapsedSeconds)).monospacedDigit() } minimal: { Image(systemName: "waveform") }
        }
    }
    private static func elapsed(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}

public struct FinishCaptureIntent: AppIntent {
    public static let title: LocalizedStringResource = "完成录音"
    public init() {}
    public func perform() async throws -> some IntentResult { .result() }
}
#endif
