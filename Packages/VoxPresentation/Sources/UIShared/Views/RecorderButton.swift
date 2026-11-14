import SwiftUI

@MainActor
struct RecorderButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let start: @MainActor () async -> Void
    let stop: @MainActor () async -> Void
    let cancel: @MainActor () async -> Void
    @StateObject private var controller = RecorderGestureController()
    @Environment(\.scenePhase) private var scenePhase

    private var capture: RecorderGestureController.Capture {
        .init(isRecording: isRecording, isProcessing: isProcessing, start: start, stop: stop, cancel: cancel)
    }

    var body: some View {
        Button { controller.activate(capture) } label: {
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(RecorderPressStyle(controller: controller, capture: capture))
        .modifier(RecorderGlassModifier())
        .accessibilityLabel(isRecording ? "停止录音" : "开始录音")
        .accessibilityIdentifier(isRecording ? "vox.stop.button" : "vox.record.button")
        .disabled(isProcessing)
        .onDisappear { controller.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.cancel() } }
    }
}

private struct RecorderPressStyle: PrimitiveButtonStyle {
    @ObservedObject var controller: RecorderGestureController
    let capture: RecorderGestureController.Capture
    @GestureState private var pressed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($pressed) { _, state, _ in state = true }
                .onChanged { value in
                    if abs(value.translation.width) > 80 || abs(value.translation.height) > 80 {
                        controller.cancel()
                    } else {
                        controller.pressBegan(capture)
                    }
                }
                .onEnded { _ in controller.pressEnded() })
            .onChange(of: pressed) { _, value in
                if !value { controller.gestureReset() }
            }
            .focusable()
            .accessibilityAction { configuration.trigger() }
            .onKeyPress(.space) { configuration.trigger(); return .handled }
            .onKeyPress(.return) { configuration.trigger(); return .handled }
    }
}

struct RecorderGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(.thickMaterial, in: .capsule) }
        else { content.glassEffect(.regular.interactive(), in: .capsule) }
    }
}
