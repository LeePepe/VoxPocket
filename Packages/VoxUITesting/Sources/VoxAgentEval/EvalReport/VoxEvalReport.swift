// VoxEvalReport.swift
// VoxPocket Agent 评估报告模型
// 汇总多次 EvalResult，生成可导出的评估报告

import Foundation

// MARK: - EvalContext（评估上下文）

/// 描述本次截图评估的期望上下文
public struct EvalContext: Sendable, Codable {
    /// 简短描述当前 UI 状态（例如"空闲状态"）
    public let sceneName: String
    /// 评估期望列表（例如["录音按钮可见", "无错误提示"]）
    public let expectations: [String]
    /// 其他附加说明（可选）
    public let notes: String?

    public init(sceneName: String, expectations: [String], notes: String? = nil) {
        self.sceneName = sceneName
        self.expectations = expectations
        self.notes = notes
    }
}

// MARK: - EvalResult（单次评估结果）

/// 单次截图 AI 评估结果
public struct EvalResult: Sendable, Codable {
    /// 评估场景名称
    public let sceneName: String
    /// 是否通过全部期望
    public let passed: Bool
    /// 发现的问题列表（未通过时填写）
    public let findings: [String]
    /// 改进建议
    public let suggestions: [String]
    /// Claude 原始响应文本
    public let rawResponse: String
    /// 评估时间戳
    public let timestamp: Date
    /// 若跳过（无 API key），说明原因
    public let skipReason: String?

    public init(
        sceneName: String,
        passed: Bool,
        findings: [String] = [],
        suggestions: [String] = [],
        rawResponse: String = "",
        timestamp: Date = Date(),
        skipReason: String? = nil
    ) {
        self.sceneName = sceneName
        self.passed = passed
        self.findings = findings
        self.suggestions = suggestions
        self.rawResponse = rawResponse
        self.timestamp = timestamp
        self.skipReason = skipReason
    }

    /// 构造跳过结果
    public static func skipped(sceneName: String, reason: String) -> EvalResult {
        EvalResult(
            sceneName: sceneName,
            passed: true,   // 跳过视为非失败
            rawResponse: "",
            skipReason: reason
        )
    }
}

// MARK: - EvalReport（评估报告）

/// 聚合多次 EvalResult 的完整报告
public struct EvalReport: Sendable, Codable {
    /// 报告标题
    public let title: String
    /// 包含的所有单次评估结果
    public let results: [EvalResult]
    /// 报告生成时间
    public let generatedAt: Date

    public init(title: String, results: [EvalResult], generatedAt: Date = Date()) {
        self.title = title
        self.results = results
        self.generatedAt = generatedAt
    }

    // MARK: 统计

    /// 总评估次数
    public var totalCount: Int { results.count }

    /// 通过次数（包括跳过）
    public var passedCount: Int { results.filter(\.passed).count }

    /// 失败次数
    public var failedCount: Int { results.filter { !$0.passed }.count }

    /// 跳过次数
    public var skippedCount: Int { results.filter { $0.skipReason != nil }.count }

    /// 通过率（0.0 – 1.0），跳过项不计入分母
    public var passRate: Double {
        let evaluated = totalCount - skippedCount
        guard evaluated > 0 else { return 1.0 }
        let passed = results.filter { $0.skipReason == nil && $0.passed }.count
        return Double(passed) / Double(evaluated)
    }

    /// 所有失败结果
    public var failures: [EvalResult] { results.filter { !$0.passed } }

    /// 汇总所有唯一发现（去重）
    public var allFindings: [String] {
        Array(Set(results.flatMap(\.findings))).sorted()
    }

    /// 汇总所有唯一建议（去重）
    public var allSuggestions: [String] {
        Array(Set(results.flatMap(\.suggestions))).sorted()
    }

    // MARK: 导出

    /// 以 JSON 格式导出报告
    public func exportJSON(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// 以可读纯文本格式导出报告
    public func exportText() -> String {
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        lines.append("╔══════════════════════════════════════════╗")
        lines.append("║     VoxPocket Agent Evaluation Report     ║")
        lines.append("╚══════════════════════════════════════════╝")
        lines.append("标题: \(title)")
        lines.append("生成时间: \(formatter.string(from: generatedAt))")
        lines.append("")
        lines.append("── 统计 ─────────────────────────────────────")
        lines.append("总计: \(totalCount) | 通过: \(passedCount) | 失败: \(failedCount) | 跳过: \(skippedCount)")
        lines.append("通过率: \(String(format: "%.1f", passRate * 100))%")
        lines.append("")

        if !failures.isEmpty {
            lines.append("── 失败项 ──────────────────────────────────")
            for failure in failures {
                lines.append("✗ \(failure.sceneName)")
                for f in failure.findings { lines.append("  · \(f)") }
            }
            lines.append("")
        }

        if !allSuggestions.isEmpty {
            lines.append("── 改进建议 ─────────────────────────────────")
            for s in allSuggestions { lines.append("  → \(s)") }
            lines.append("")
        }

        lines.append("── 详细结果 ─────────────────────────────────")
        for result in results {
            let icon = result.skipReason != nil ? "⊘" : (result.passed ? "✓" : "✗")
            lines.append("\(icon) \(result.sceneName)")
            if let skip = result.skipReason {
                lines.append("  跳过原因: \(skip)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// 将报告写入指定 URL
    public func save(to url: URL, format: ExportFormat = .json) throws {
        switch format {
        case .json:
            let data = try exportJSON()
            try data.write(to: url)
        case .text:
            let text = exportText()
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public enum ExportFormat: Sendable {
        case json
        case text
    }
}

// MARK: - EvalReport.Builder（流式构建器）

extension EvalReport {
    /// 用于在测试套件中逐步积累结果的构建器
    public final class Builder: @unchecked Sendable {
        private var results: [EvalResult] = []
        private let title: String

        public init(title: String) {
            self.title = title
        }

        /// 追加单条评估结果
        public func append(_ result: EvalResult) {
            results.append(result)
        }

        /// 生成最终报告（不可变）
        public func build() -> EvalReport {
            EvalReport(title: title, results: results)
        }
    }
}
