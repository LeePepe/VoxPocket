import Foundation
import LokiKit

/// 本地诊断日志只发送审核过的固定消息和数值；动态文本留在上传边界之外。
@MainActor
enum VoxPocketLogging {
    static let localLoggingEnabledKey = "VoxPocketLocalLokiLoggingEnabled"
    private static let localEndpoint = URL(string: "http://localhost:3100/loki/api/v1/push")
    private static var worker: Task<Void, Never>?

    static func start(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard worker == nil, let endpoint = endpoint(environment: environment) else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        let labels = [
            "app": "VoxPocket",
            "env": "local",
            "version": info["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info["CFBundleVersion"] as? String ?? "unknown"
        ]
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let sink = LokiLogSink(
            endpoint: endpoint, labels: labels,
            allowedMessages: allowedMessages, allowedContextKeys: allowedContextKeys,
            persistenceURL: directory?.appendingPathComponent("VoxPocket/logs/pending.json"),
            token: environment["LOKI_TOKEN"]
        )
        PrintLogger.configureRemoteSink(sink)
        worker = sink.start()
        PrintLogger(subsystem: "Logging").info("Local log collection started")
    }

    static func endpoint(environment: [String: String], defaults: UserDefaults = .standard) -> URL? {
        if let raw = environment["LOKI_ENDPOINT"] {
            guard let url = URL(string: raw), let host = url.host, !host.isEmpty,
                  ["http", "https"].contains(url.scheme),
                  url.user == nil, url.password == nil else { return nil }
            return url
        }
        #if os(macOS)
        // 持久化设置仅允许本机端点；错误类型按关闭处理，避免意外启用上传。
        if let choice = defaults.object(forKey: localLoggingEnabledKey) {
            guard let enabled = choice as? Bool, enabled else { return nil }
            return localEndpoint
        }
        #endif
        #if DEBUG && os(macOS)
        return localEndpoint
        #else
        return nil
        #endif
    }

    static let allowedContextKeys: Set<String> = [
        "duration_ms", "char_count", "call_count", "input_length", "output_length",
        "text_length", "transcription_length", "refined_length", "length", "count",
        "error_code", "status", "elapsed_ms", "retry_count"
    ]

    // 精确匹配：未审核消息（包括错误描述、转写、prompt）统一替换，不能做前缀放行。
    static let allowedMessages: Set<String> = [
        "Local log collection started", "Initialized", "Initialization complete",
        "Services initialized", "Application did finish launching", "Application will terminate",
        "Applied LLM analysis settings", "Configured LLM provider",
        "LLM configuration failed; using fallback", "SwiftData persistence initialized",
        "Failed to initialize SwiftData persistence", "Recording started", "Recording ended",
        "Recording stopped", "Recording cancelled", "Start recording requested",
        "Recording request rejected because another source is active",
        "Start recording ignored because recorder is busy", "Stop requested while start is in progress",
        "Stop recording ignored because recorder is not listening",
        "Showing existing window", "Created and showing window", "Hiding window", "Closed window",
        "Registered show panel hotkey", "Failed to register show panel hotkey",
        "Registered quick record hotkey", "Show panel hotkey triggered",
        "Quick record start triggered", "Quick record stop triggered",
        "Recording source mismatch on quick record stop", "Received live transcription update",
        "Prepared text for refinement", "Refinement completed", "Refinement stream completed",
        "Refinement failed, fallback to raw transcription", "Applied refined text to editor",
        "Pasted refined text", "Auto-copied refined text", "Paste simulation failed",
        "Inserted text into focused element", "Replaced selected text in focused element",
        "Appended to Claude inbox", "Auto-stopping recording after inactivity",
        "Reset auto-stop timer after transcription update", "Already transcribing, stopping first",
        "Recording + Apple Speech started", "No audio file", "stop() called",
        "WhisperKit model preloaded and ready", "Merging Apple Speech + Whisper via LLM",
        "开始内容分析", "内容分析完成", "开始文本优化", "文本优化完成",
        "开始流式文本优化", "流式文本优化完成", "流式文本优化失败",
        "意图分析完成", "意图分析失败", "语气分析完成", "语气分析失败",
        "Azure completion succeeded", "调用 Azure Foundry"
    ]
}
