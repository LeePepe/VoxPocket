import SwiftUI
import CoreModels
import UIShared
#if os(macOS)
import AppKit
#endif

@main
struct VoxTodoPreviewHostEntry {
    static func main() async {
        #if os(macOS)
        let args = CommandLine.arguments
        if let snapshotIdx = args.firstIndex(of: "--snapshot-board"), snapshotIdx + 1 < args.count {
            let outputFile = args[snapshotIdx + 1]
            let code = await LocalBoardSnapshotExporter.exportBoardSnapshot(to: URL(fileURLWithPath: outputFile))
            exit(code)
        }

        await MainActor.run {
            let app = NSApplication.shared
            let delegate = PreviewHostAppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.run()
        }
        #endif
    }
}

#if os(macOS)
@MainActor
final class LocalPreviewChooserState: ObservableObject {
    @Published var selectedVariant: TodoUnfoldVariantKind = .v01
    @Published var starredVariants: Set<TodoUnfoldVariantKind> = [.v01, .v02]
    @Published var notesByVariant: [TodoUnfoldVariantKind: String] = [
        .v01: "DI-v01 经典三段层叠岛 + 横滑子步骤 Edge-to-Edge 切边在灵动岛边界",
        .v02: "Todo 卡片 v02 同框裁剪标签架 + 左下竖向 Liquid Glass Filter",
        .v03: "",
        .v04: ""
    ]
    @Published var copiedToastVisible: Bool = false

    func toggleStar(_ kind: TodoUnfoldVariantKind) {
        if starredVariants.contains(kind) {
            starredVariants.remove(kind)
        } else {
            starredVariants.insert(kind)
        }
    }

    func buildSelectionSummary() -> String {
        var lines: [String] = []
        lines.append("SELECTED: todo-swiftui/\(selectedVariant.rawValue) (\(selectedVariant.title))")
        let stars = TodoUnfoldVariantKind.allCases
            .filter { starredVariants.contains($0) }
            .map { "todo-swiftui/\($0.rawValue)" }
        lines.append("STARRED: \(stars.isEmpty ? "none" : stars.joined(separator: ", "))")
        for kind in TodoUnfoldVariantKind.allCases {
            let note = (notesByVariant[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                lines.append("NOTES [todo-swiftui/\(kind.rawValue)]: \(note)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func copySelectionSummaryToPasteboard() {
        let summary = buildSelectionSummary()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(summary, forType: .string)
        copiedToastVisible = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            self.copiedToastVisible = false
        }
    }
}

@MainActor
struct LocalNativePreviewHostRootView: View {
    @StateObject private var chooser = LocalPreviewChooserState()

    var body: some View {
        VStack(spacing: 0) {
            TodoUnfoldFourUpPreviewBoard()

            Divider()

            nativeChooserFooterBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
    }

    private var nativeChooserFooterBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(TodoUnfoldVariantKind.allCases) { kind in
                    let isSelected = chooser.selectedVariant == kind
                    let isStarred = chooser.starredVariants.contains(kind)

                    HStack(spacing: 4) {
                        Button(action: { chooser.selectedVariant = kind }) {
                            HStack(spacing: 4) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.caption.weight(.bold))
                                Text("SELECT \(kind.badgeCode)")
                                    .font(.caption.weight(.bold).monospaced())
                            }
                            .foregroundStyle(isSelected ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: { chooser.toggleStar(kind) }) {
                            Image(systemName: isStarred ? "star.fill" : "star")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isStarred ? Color.orange : .secondary)
                                .frame(width: 26, height: 26)
                                .background(Color.primary.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField(
                "记录对 \(chooser.selectedVariant.badgeCode) 的评审备注 (NOTES)…",
                text: Binding(
                    get: { chooser.notesByVariant[chooser.selectedVariant] ?? "" },
                    set: { chooser.notesByVariant[chooser.selectedVariant] = $0 }
                )
            )
            .font(.caption)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 220, maxWidth: .infinity)

            Button(action: { chooser.copySelectionSummaryToPasteboard() }) {
                Label(
                    chooser.copiedToastVisible ? "已复制 Summary" : "复制 Selection Summary",
                    systemImage: chooser.copiedToastVisible ? "checkmark.circle.fill" : "doc.on.clipboard"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(chooser.copiedToastVisible ? Color.green : Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
final class PreviewHostAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rootView = LocalNativePreviewHostRootView()
        let hostingView = NSHostingView(rootView: rootView)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1720, height: 1020)
        let width = min(1720, max(1280, screenFrame.width - 24))
        let height = min(1020, max(820, screenFrame.height - 24))
        let rect = NSRect(
            x: screenFrame.minX + (screenFrame.width - width) / 2,
            y: screenFrame.minY + (screenFrame.height - height) / 2,
            width: width,
            height: height
        )

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoxPocket · 120Hz 原生 SwiftUI 预览窗 (Todo 竖向筛选 · 录音 5 阶段 · 灵动岛 DI-v01..v04 · Tab 4 macOS 桌面工作台)"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let autoShotPath = ProcessInfo.processInfo.environment["VOX_PREVIEW_AUTOSHOT"], !autoShotPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                _ = LocalBoardSnapshotExporter.captureViewPNG(hostingView, to: URL(fileURLWithPath: autoShotPath))
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
enum LocalBoardSnapshotExporter {
    static func exportBoardSnapshot(to outputURL: URL) async -> Int32 {
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return 1
        }
        let board = LocalNativePreviewHostRootView()
            .environment(\.colorScheme, .dark)
            .frame(width: 1680, height: 1140)
        let host = NSHostingView(rootView: board)
        host.frame = NSRect(x: 0, y: 0, width: 1680, height: 1140)
        let panel = NSPanel(
            contentRect: NSRect(x: -10000, y: -10000, width: 1680, height: 1140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }

        try? await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded()
        return captureViewPNG(host, to: outputURL) ? 0 : 1
    }

    static func captureViewPNG(_ view: NSView, to url: URL) -> Bool {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return false
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
#endif
