import SwiftUI

/// Six semantic aura phases aligned with `AtmosphereGlass` gem-tone palette (`#52BDB8`, `#578FE6`, `#9480E6`, `#57BD99`, `#38BDF8`, `#E67580`).
public enum VoxCaptureIslandPhase: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case listening
    case transcribing
    case refining
    case completedReceipt
    case todoFocusPinned
    case errorAlert

    public var primaryHex: String {
        switch self {
        case .listening:        "#52BDB8"
        case .transcribing:     "#578FE6"
        case .refining:         "#9480E6"
        case .completedReceipt: "#57BD99"
        case .todoFocusPinned:  "#38BDF8"
        case .errorAlert:       "#E67580"
        }
    }

    public var accentColor: Color {
        switch self {
        case .listening:
            Color(.sRGB, red: 0.32, green: 0.74, blue: 0.72, opacity: 1.0)
        case .transcribing:
            Color(.sRGB, red: 0.34, green: 0.56, blue: 0.90, opacity: 1.0)
        case .refining:
            Color(.sRGB, red: 0.58, green: 0.50, blue: 0.90, opacity: 1.0)
        case .completedReceipt:
            Color(.sRGB, red: 0.34, green: 0.74, blue: 0.60, opacity: 1.0)
        case .todoFocusPinned:
            Color(.sRGB, red: 0.22, green: 0.74, blue: 0.97, opacity: 1.0)
        case .errorAlert:
            Color(.sRGB, red: 0.90, green: 0.46, blue: 0.50, opacity: 1.0)
        }
    }

    public var symbolName: String {
        switch self {
        case .listening: "waveform"
        case .transcribing: "waveform.badge.magnifyingglass"
        case .refining: "sparkles"
        case .completedReceipt: "checkmark.circle.fill"
        case .todoFocusPinned: "timer"
        case .errorAlert: "exclamationmark.triangle.fill"
        }
    }

    public var localizedPhaseTitle: String {
        switch self {
        case .listening: "正在聆听"
        case .transcribing: "转译中…"
        case .refining: "AI 提炼中…"
        case .completedReceipt: "已存入待办"
        case .todoFocusPinned: "焦点盯防"
        case .errorAlert: "需要重试"
        }
    }
}

public struct VoxIslandSubtaskPayload: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var isCompleted: Bool

    public init(id: String = UUID().uuidString, title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = String(title.prefix(28))
        self.isCompleted = isCompleted
    }
}

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import AppIntents
import WidgetKit

public struct VoxCaptureActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var mode: String
        public var elapsedSeconds: Int
        public var isRecording: Bool
        public var phase: VoxCaptureIslandPhase
        public var todoID: String?
        public var title: String
        public var subtitle: String?
        public var priorityBadge: String
        public var subtasks: [VoxIslandSubtaskPayload]
        public var completedSubtasks: Int
        public var totalSubtasks: Int
        public var statusReceiptText: String?

        public init(
            mode: String,
            elapsedSeconds: Int = 0,
            isRecording: Bool = true,
            phase: VoxCaptureIslandPhase = .listening,
            todoID: String? = nil,
            title: String = "正在聆听…",
            subtitle: String? = nil,
            priorityBadge: String = "P0",
            subtasks: [VoxIslandSubtaskPayload] = [],
            completedSubtasks: Int = 0,
            totalSubtasks: Int = 0,
            statusReceiptText: String? = nil
        ) {
            self.mode = mode
            self.elapsedSeconds = elapsedSeconds
            self.isRecording = isRecording
            self.phase = phase
            self.todoID = todoID
            self.title = String(title.prefix(24))
            self.subtitle = subtitle.map { String($0.prefix(64)) }
            self.priorityBadge = priorityBadge
            self.subtasks = Array(subtasks.prefix(3))
            self.completedSubtasks = completedSubtasks
            self.totalSubtasks = totalSubtasks
            self.statusReceiptText = statusReceiptText
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
            let accent = context.state.phase.accentColor
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: context.state.phase.symbolName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title.isEmpty ? context.state.mode : context.state.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.state.statusReceiptText ?? context.state.phase.localizedPhaseTitle)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(accent)
                    }
                    Spacer()
                    if context.state.isRecording {
                        Button(intent: FinishCaptureIntent()) {
                            Label("完成", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityLabel("完成录音")
                    } else if let todoID = context.state.todoID, !todoID.isEmpty {
                        HStack(spacing: 6) {
                            Button(intent: TodoIslandActionIntent(actionKind: "done", todoID: todoID)) {
                                Image(systemName: "circle")
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)

                            Button(intent: TodoIslandActionIntent(actionKind: "snooze15m", todoID: todoID)) {
                                Text("⏰ +15m")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.88))
        } dynamicIsland: { context in
            let accent = context.state.phase.accentColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phase.localizedPhaseTitle, systemImage: context.state.phase.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isRecording {
                        Text(Self.elapsed(context.state.elapsedSeconds))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(accent)
                            .contentTransition(.numericText())
                    } else {
                        Text(context.state.statusReceiptText ?? "\(context.state.completedSubtasks)/\(max(1, context.state.totalSubtasks))")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(accent)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if context.state.isRecording {
                            HStack {
                                Text(context.state.mode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(intent: FinishCaptureIntent()) {
                                    Label("完成录音", systemImage: "stop.circle.fill")
                                        .font(.caption.weight(.bold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(accent)
                            }
                        } else {
                            if let desc = context.state.subtitle, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(desc)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                            }

                            if !context.state.subtasks.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(context.state.subtasks) { sub in
                                            Button(intent: TodoIslandActionIntent(actionKind: "subtask", todoID: context.state.todoID ?? "")) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                                                        .font(.caption2.weight(.bold))
                                                    Text(sub.title)
                                                        .font(.caption2.weight(.medium))
                                                        .lineLimit(1)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            }

                            if let todoID = context.state.todoID, !todoID.isEmpty {
                                HStack(spacing: 8) {
                                    Button(intent: ToggleQuickCaptureIntent()) {
                                        Text("🎙️ 语音补录")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)

                                    Button(intent: TodoIslandActionIntent(actionKind: "aiDoIt", todoID: todoID)) {
                                        Text("✨ AI 直接做")
                                            .font(.caption2.weight(.bold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(accent)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase.symbolName)
                    .foregroundStyle(accent)
            } compactTrailing: {
                if context.state.isRecording {
                    Text(Self.elapsed(context.state.elapsedSeconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                } else {
                    Text(context.state.phase.localizedPhaseTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                }
            } minimal: {
                Image(systemName: context.state.phase.symbolName)
                    .foregroundStyle(accent)
            }
        }
    }

    public static let stopRecordingURL = URL(string: "voxpocket://stopRecording")!
    private static func elapsed(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

@available(iOS 18.0, *)
public struct TodoIslandActionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "灵动岛待办原位操作"
    public static let description = IntentDescription("在灵动岛上直接勾选子任务、一键完成、+15m 延后或顺延至习惯锚点")
    public static let openAppWhenRun: Bool = false
    public static let didRequestActionNotification = Notification.Name("vox.liveActivity.todoAction")
    @MainActor public static var performHandler: ((_ actionKind: String, _ todoID: String) async -> Void)?

    @Parameter(title: "动作类型")
    public var actionKind: String

    @Parameter(title: "待办 ID")
    public var todoID: String

    public init() {
        self.actionKind = "done"
        self.todoID = ""
    }

    public init(actionKind: String, todoID: String) {
        self.actionKind = actionKind
        self.todoID = todoID
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let handler = Self.performHandler {
            await handler(actionKind, todoID)
        } else {
            NotificationCenter.default.post(
                name: Self.didRequestActionNotification,
                object: nil,
                userInfo: ["actionKind": actionKind, "todoID": todoID]
            )
        }
        return .result()
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

