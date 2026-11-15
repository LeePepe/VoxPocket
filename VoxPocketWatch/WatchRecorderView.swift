import SwiftUI
import VoxPocketKit

struct WatchRecorderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: WatchRecorderViewModel
    // 快照宿主注入只读辅助功能状态；普通启动使用系统环境值。
    private let reducedEffectsOverride: Bool?

    init(model: @autoclosure @escaping () -> WatchRecorderViewModel, reducedEffects: Bool? = nil) {
        _model = StateObject(wrappedValue: model())
        reducedEffectsOverride = reducedEffects
    }
    private var palette: WatchTheme.Palette { WatchTheme.palette(for: colorScheme) }
    private var usesReducedMotion: Bool { reducedEffectsOverride ?? reduceMotion }
    private var usesReducedTransparency: Bool { reducedEffectsOverride ?? reduceTransparency }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    if !keepsRecorderFirst, receiptText != nil { latestReceipt }
                    recorderStage(diameter: min(104, max(72, min(geometry.size.width * 0.56, geometry.size.height * 0.36))))
                    if keepsRecorderFirst, receiptText != nil { latestReceipt }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .background(palette.canvas)
            .foregroundStyle(palette.primaryText)
            .accessibilityElement(children: .contain)
        }
    }
    private var keepsRecorderFirst: Bool { model.state == .recording || model.actionLocked }
    private var latestReceipt: some View {
        VStack(spacing: 4) {
            if let text = receiptText { receipt(text) }
            if model.canRetry {
                Button { model.retry() } label: {
                    Text(retryButtonTitle).foregroundStyle(palette.primaryText)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(WatchTheme.cyan)
                .accessibilityHint("使用同一段已保留录音重新同步")
            }
        }
    }
    private var retryButtonTitle: String {
        if case .failed = model.state { return "重试" }
        return "重试未同步录音"
    }
    private func recorderStage(diameter: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(stateText).font(.caption).foregroundStyle(palette.secondaryText).multilineTextAlignment(.center)
            ViewThatFits(in: .horizontal) {
                orb(diameter: diameter)
                orb(diameter: 72)
            }
            WaveformView(levels: model.levels)
                .animation(usesReducedMotion ? nil : .linear(duration: 0.1), value: model.levels)
                .accessibilityHidden(true)
            Text(durationText).font(.system(.headline, design: .monospaced).monospacedDigit())
                .foregroundStyle(palette.primaryText)
                .accessibilityLabel("录音时长 \(durationText)")
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder
    private func orb(diameter: CGFloat) -> some View {
        if usesReducedTransparency {
            primaryButton()
                .background(isRecording ? WatchTheme.coral : WatchTheme.cyan, in: Circle())
                .buttonStyle(.plain)
                .frame(width: diameter, height: diameter)
        } else {
            primaryButton()
                .background((isRecording ? WatchTheme.coral : WatchTheme.cyan).opacity(0.22), in: Circle())
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(width: diameter, height: diameter)
        }
    }
    private func primaryButton() -> some View {
        Button(action: model.toggle) {
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.title2).foregroundStyle(usesReducedTransparency ? WatchTheme.solidGlyph : palette.primaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(model.actionLocked)
        .accessibilityLabel(isRecording ? "停止录音" : "开始录音")
        .accessibilityHint(isRecording ? "结束并发送录音" : "开始新的录音")
    }
    private func receipt(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(palette.primaryText)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(text)
    }
    private var isRecording: Bool { model.state == .recording || model.state == .stopping }
    private var durationText: String {
        let seconds = Int(model.duration.isFinite ? max(0, min(model.duration, WatchCaptureMetadata.maxDuration)) : 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private var stateText: String {
        switch model.state {
        case .starting: "正在准备录音…"
        case .stopping: "正在保存录音…"
        case .recording: "正在录音 · 点击停止"
        case .transferring: model.queuedOffline ? "等待 iPhone 连接" : "正在发往 iPhone"
        case .processing: "iPhone 正在处理"
        default: "点击录音"
        }
    }
    private var receiptText: String? {
        if case .failed(let reason) = model.state { return reason }
        guard let receipt = model.lastReceipt else { return nil }
        switch receipt.status {
        case .transferring: return "📤 正在发往 iPhone…"
        case .processingOnPhone: return "⏳ iPhone 正在提炼待办…"
        case .todoAdded(_, let title, _): return "✅ 已添加手机 Todo：\(title)"
        case .failed: return "未能同步，请在 iPhone 打开 VoxPocket 后重试"
        }
    }
}

private struct WaveformView: View {
    let levels: [Float]
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule().fill(WatchTheme.cyan).frame(width: 3, height: CGFloat(max(2, min(24, 2 + level * 22))))
            }
        }.frame(height: 24)
    }
}
