#if os(macOS)
import Foundation
import Observability

/// macOS Claude inbox 服务实现
///
/// 将转录文本追加写入 `~/.claude/inbox.md`，触发 Claude Code 自动计划流程。
public final class MacOSClaudeInboxService: ClaudeInboxService, @unchecked Sendable {

    public static let shared = MacOSClaudeInboxService()

    private let inboxURL: URL
    private let logger: Logger = PrintLogger(subsystem: "ClaudeInbox")

    private init() {
        inboxURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/inbox.md")
    }

    public func appendToInbox(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = "\n\(trimmed)\n"

        guard let data = entry.data(using: .utf8) else {
            throw ClaudeInboxError.encodingFailed
        }

        if FileManager.default.fileExists(atPath: inboxURL.path) {
            let handle = try FileHandle(forWritingTo: inboxURL)
            handle.seekToEndOfFile()
            handle.write(data)
            try handle.close()
        } else {
            try data.write(to: inboxURL, options: .atomic)
        }

        logger.log(.debug, "Appended to Claude inbox", context: ["char_count": trimmed.count])
    }
}

public enum ClaudeInboxError: LocalizedError {
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode text for Claude inbox"
        }
    }
}
#endif
