import AppKit
import SwiftUI
import OSLog

// 只替换配置与窗口内容；@main 入口由 runner 从生产源码原样提取。
@MainActor enum LLMAppConfig {
    static let load = Task {
        try await Task.sleep(for: .milliseconds(100))
    }
    static func loadRuntimeConfiguration() async throws { try await load.value }
}

enum PrivateModelConfigurationError: Error {
    var errorDescription: String? { "fixture configuration failure" }
}

@MainActor final class ProbeState: ObservableObject {
    static let shared = ProbeState()
    @Published var clicked = false
    @Published var ready = false
    var taskRan = false
    var mainQueueRan = false
    var rendered = false
}

@MainActor func onRunLoop(after interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
    let timer = Timer(timeInterval: interval, repeats: false) { _ in
        MainActor.assumeIsolated { action() }
    }
    RunLoop.main.add(timer, forMode: .common)
}

struct ProbeContent: View {
    @ObservedObject var state = ProbeState.shared
    var body: some View {
        ZStack {
            Button("Test action") {
                state.clicked = true
                Task { @MainActor in state.taskRan = true }
            }
            .buttonStyle(.borderless)
            .frame(width: 180, height: 50)
            .contentShape(Rectangle())
            .position(x: 140, y: 60)
            Text(state.clicked ? "Changed" : "Initial")
                .onChange(of: state.clicked) { _, _ in state.rendered = true }
                .position(x: 140, y: 105)
        }
        .frame(width: 280, height: 120)
    }
}

@MainActor func press(_ window: NSWindow) {
    let point = NSPoint(x: window.contentLayoutRect.midX, y: window.contentLayoutRect.midY)
    for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        if let event = NSEvent.mouseEvent(
            with: kind, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ) {
            // 仅投递到测试进程自身，不向桌面或其他 App 注入事件。
            NSApp.postEvent(event, atStart: false)
        }
    }
}

struct VoxPocketApp: App {
    @ObservedObject var state = ProbeState.shared

    init() {
        DispatchQueue.main.async { ProbeState.shared.mainQueueRan = true }
        Task { @MainActor in
            try await LLMAppConfig.loadRuntimeConfiguration()
            ProbeState.shared.ready = true
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
            print("FAIL: startup watchdog expired")
            exit(2)
        }
        onRunLoop(after: 1) {
            guard let window = NSApp.windows.first else { exit(2) }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            onRunLoop(after: 0.5) {
                press(window)
                onRunLoop(after: 0.2) { press(window) }
                onRunLoop(after: 1) {
                    let state = ProbeState.shared
                    let passed = state.ready && state.clicked && state.taskRan
                        && state.mainQueueRan && state.rendered
                    print("ready=\(state.ready) clicked=\(state.clicked) task=\(state.taskRan) main_queue=\(state.mainQueueRan) rendered=\(state.rendered)")
                    print(passed ? "PASS: startup interaction" : "FAIL: startup interaction")
                    exit(passed ? 0 : 1)
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup("VoxPocket startup regression") {
            if state.ready { ProbeContent() }
            else { ProgressView().frame(width: 280, height: 120) }
        }
    }
}
