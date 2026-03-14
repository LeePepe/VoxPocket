import Foundation

/// Claude inbox 服务协议
///
/// 将转录文本写入 ~/.claude/inbox.md，触发 Claude Code 的自动计划流程。
public protocol ClaudeInboxService: AnyObject, Sendable {

    /// 将文本追加写入 Claude inbox
    ///
    /// - Parameter text: 要写入的转录/优化文本
    /// - Throws: `ClaudeInboxError` 如果写入失败
    func appendToInbox(_ text: String) async throws
}
