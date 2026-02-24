import AppIntents
import SwiftUI
import WidgetKit

/// Control Center 录音控件 (iOS 18+)
///
/// 在控制中心显示录音按钮，点按后启动 VoxPocket 并自动开始语音识别。
#if os(iOS)
@available(iOSApplicationExtension 18.0, *)
public struct VoxPocketControlWidget: ControlWidget {
    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tianpli.VoxPocket.Recording") {
            ControlWidgetButton(action: StartRecordingControlIntent()) {
                Label("录音", systemImage: "mic.fill")
            }
        }
        .displayName("VoxPocket 录音")
        .description("点按开始语音识别")
    }
}

/// Control Center 专用 Intent
///
/// 与主 app 的 StartRecordingIntent 功能相同，
/// 但定义在 Widget Extension 中以避免跨 target 依赖。
@available(iOS 18.0, *)
struct StartRecordingControlIntent: AppIntent {
    static var title: LocalizedStringResource { "开始录音" }
    static var description: IntentDescription { IntentDescription("启动 VoxPocket 并开始语音识别") }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
#endif
