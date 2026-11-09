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
            ControlWidgetButton(action: ToggleQuickCaptureIntent()) {
                Label("快速录音", systemImage: "waveform.and.mic")
            }
        }
        .displayName("VoxPocket 录音")
        .description("无需打开 App，点按后台开启或停止语音录入")
    }
}
#endif
