#if os(macOS)
import SwiftUI

/// 与主窗口共用实际绘制组件；浮窗由电平事件驱动，不新增连续刷新时间轴。
@MainActor
public struct QuickRecordingPhaseSurface: View {
    private let status: RecorderStatus
    private let audioLevel: Double?

    public init(status: RecorderStatus, audioLevel: Double? = nil) {
        self.status = status
        self.audioLevel = audioLevel
    }

    public var body: some View {
        BackgroundAtmosphere(status: status, audioLevel: audioLevel, tracksAudioContinuously: false)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#endif
