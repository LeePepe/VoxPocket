import SwiftUI

struct RecorderBackdrop: View {
    let status: RecorderStatus
    let audioLevel: Float
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.surfacePrimary
            BackgroundAtmosphere(status: status, audioLevel: Double(audioLevel))
                .opacity(colorScheme == .light ? 0.28 : 1)
        }
        .ignoresSafeArea()
    }
}

struct RecorderSentenceStage: View {
    let sentence: String
    let copy: () -> Void
    @ScaledMetric(relativeTo: .title2) private var sentenceSize = 25.0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Text(sentence)
                    .font(.system(size: sentenceSize, weight: .semibold, design: .rounded))
                    .tracking(-0.4).lineSpacing(7).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: copy)
                    .accessibilityIdentifier("vox.transcript.final")
                    .accessibilityLabel(sentence)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct RecorderDock: View {
    let isRecording: Bool
    let isProcessing: Bool
    let audioLevel: Float
    let feedback: String
    let error: String?
    let start: @MainActor () async -> Void
    let stop: @MainActor () async -> Void
    let cancel: @MainActor () async -> Void
    let retry: () -> Void
    let openTodos: () -> Void
    let openSettings: () -> Void
    @State private var foldExpanded = false
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
    }

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                if foldExpanded { destinations.transition(.opacity) }
                HStack(spacing: 14) {
                    Button {
                        withAnimation(reduceMotion ? nil : AppTheme.gestureSpring) { foldExpanded.toggle() }
                    } label: {
                        Image(systemName: foldExpanded ? "xmark" : "square.stack.3d.up")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .modifier(RecorderGlassModifier())
                    .glassEffectID("fold", in: glass)
                    .accessibilityLabel(foldExpanded ? "收起菜单" : "展开菜单")
                    .accessibilityIdentifier("vox.fold.menu.button")
                    Spacer(minLength: 0)
                    waveform
                    Spacer(minLength: 0)
                    RecorderButton(isRecording: isRecording, isProcessing: isProcessing, start: start, stop: stop, cancel: cancel)
                        .glassEffectID("record", in: glass)
                }
                feedbackRegion
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, minHeight: 148)
        }
        .background {
            ZStack {
                if reduceTransparency { shape.fill(.thickMaterial) }
                else {
                    shape.fill(AppTheme.surfacePrimary.opacity(0.78))
                    RecorderCaustics(level: audioLevel, active: isRecording)
                }
            }
            .clipShape(shape)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var destinations: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { todoButton; settingsButton; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 14) { todoButton; settingsButton }
        }
    }

    private var todoButton: some View {
        Button(action: openTodos) {
            Label("待办", systemImage: "checklist").padding(.horizontal, 16).frame(minHeight: 44)
        }
        .buttonStyle(.plain).modifier(RecorderGlassModifier())
        .glassEffectID("todos", in: glass)
        .accessibilityIdentifier("vox.fold.todoList.button")
    }

    private var settingsButton: some View {
        Button(action: openSettings) {
            Label("设置", systemImage: "gearshape").padding(.horizontal, 16).frame(minHeight: 44)
        }
        .buttonStyle(.plain).modifier(RecorderGlassModifier())
        .glassEffectID("settings", in: glass)
        .accessibilityIdentifier("vox.fold.settings.button")
    }

    private var waveform: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .indigo], startPoint: .bottom, endPoint: .top))
                    .frame(width: 4, height: barHeight(index))
            }
        }
        .frame(height: 32)
        .opacity(isRecording ? 1 : 0.45)
        .animation(reduceMotion ? nil : AppTheme.gestureSpring, value: audioLevel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRecording ? "正在录音" : "准备录音")
        .accessibilityIdentifier("vox.recording.indicator")
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let level = audioLevel.isFinite ? min(1, max(0, audioLevel)) : 0
        let amplitude = isRecording ? (reduceMotion ? 0.5 : CGFloat(level)) : 0.12
        return max(6, amplitude * [0.45, 0.7, 1, 0.6, 0.85, 0.55, 0.75][index] * 32)
    }

    private var feedbackRegion: some View {
        VStack(spacing: 4) {
            if let error {
                Text(error).font(.footnote).foregroundStyle(.primary)
                Button("重试", systemImage: "arrow.clockwise", action: retry)
                    .frame(minHeight: 44).accessibilityIdentifier("vox.capture.retry")
            } else {
                HStack(spacing: 8) {
                    if isProcessing { ProgressView().controlSize(.small) }
                    Text(feedback).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 24)
        .accessibilityIdentifier("r3-feedback")
    }
}

private struct RecorderCaustics: View {
    let level: Float
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var energy: Double {
        guard active else { return 0.12 }
        return reduceMotion ? 0.4 : Double(level.isFinite ? min(1, max(0, level)) : 0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(colors: [.cyan.opacity(0.18 + energy * 0.22), .clear], center: .bottomLeading,
                               startRadius: 0, endRadius: geometry.size.width * 0.8)
                RadialGradient(colors: [.indigo.opacity(0.14 + energy * 0.2), .clear], center: .bottomTrailing,
                               startRadius: 0, endRadius: geometry.size.width * 0.7)
            }
        }
        .animation(reduceMotion ? nil : AppTheme.gestureSpring, value: level)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
