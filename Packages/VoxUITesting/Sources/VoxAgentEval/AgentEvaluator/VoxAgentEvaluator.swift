// VoxAgentEvaluator.swift
// VoxPocket AI 视觉评估器
// 将截图发送给 Claude Vision API，由 AI 判断 UI 是否满足期望

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 协议

/// AI 视觉评估协议
public protocol AgentEvaluating: Sendable {
    /// 评估截图是否满足给定上下文中的期望
    ///
    /// - Parameters:
    ///   - screenshot: 待评估的截图
    ///   - context:    描述期望的评估上下文
    /// - Returns: 结构化评估结果
    func evaluate(screenshot: CGImage, context: EvalContext) async throws -> EvalResult
}

// MARK: - ClaudeAgentEvaluator（默认实现）

/// 使用 Claude Vision API（claude-sonnet-4-6）进行截图评估
///
/// API Key 从环境变量读取：`CLAUDE_API_KEY` 或 `ANTHROPIC_API_KEY`
/// 若均未设置，返回跳过结果而非抛出错误
public struct ClaudeAgentEvaluator: AgentEvaluating, Sendable {

    // MARK: 配置

    /// Claude API 端点
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// 使用的模型
    private let model = "claude-sonnet-4-6"
    /// 最大 token 数
    private let maxTokens = 1024
    /// Anthropic API 版本
    private let apiVersion = "2023-06-01"

    public init() {}

    // MARK: AgentEvaluating

    public func evaluate(screenshot: CGImage, context: EvalContext) async throws -> EvalResult {
        // 读取 API Key
        guard let apiKey = Self.resolveAPIKey() else {
            return .skipped(
                sceneName: context.sceneName,
                reason: "未找到 CLAUDE_API_KEY / ANTHROPIC_API_KEY 环境变量，跳过 AI 评估"
            )
        }

        // 编码截图为 base64
        guard let imageData = cgImageToPNGData(screenshot) else {
            throw VoxAgentEvalError.imageEncodingFailed
        }
        let base64Image = imageData.base64EncodedString()

        // 构建请求体
        let requestBody = buildRequestBody(
            base64Image: base64Image,
            context: context
        )

        // 发送请求
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoxAgentEvalError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<无响应体>"
            throw VoxAgentEvalError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        // 解析响应
        return try parseResponse(data: data, context: context)
    }

    // MARK: 内部辅助

    /// 从环境变量解析 API Key
    private static func resolveAPIKey() -> String? {
        ProcessInfo.processInfo.environment["CLAUDE_API_KEY"]
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    /// 构建 Claude Messages API 请求体（含 vision）
    private func buildRequestBody(base64Image: String, context: EvalContext) -> [String: Any] {
        let expectationsList = context.expectations
            .enumerated()
            .map { "  \($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let notes = context.notes.map { "\n\n附加说明：\($0)" } ?? ""

        let systemPrompt = """
        你是 VoxPocket 移动/桌面应用的 UI 质量审查助手。
        VoxPocket 是一款语音录制与 AI 转录润色应用（SwiftUI，iOS/macOS）。
        请根据用户提供的截图和期望列表，判断 UI 是否符合要求。

        输出格式（严格遵守 JSON，不要包含任何解释文字）：
        {
          "passed": true/false,
          "findings": ["发现的问题1", "发现的问题2"],
          "suggestions": ["改进建议1", "改进建议2"]
        }
        """

        let userMessage = """
        场景：\(context.sceneName)\(notes)

        期望条件：
        \(expectationsList)

        请评估截图是否满足上述所有期望条件。
        """

        return [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": userMessage
                        ]
                    ]
                ]
            ]
        ]
    }

    /// 解析 Claude API 响应为 EvalResult
    private func parseResponse(data: Data, context: EvalContext) throws -> EvalResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let rawText = content["text"] as? String else {
            throw VoxAgentEvalError.responseParsingFailed
        }

        // 尝试从响应文本中提取 JSON
        let parsed = extractJSON(from: rawText)

        let passed     = parsed["passed"] as? Bool ?? false
        let findings   = parsed["findings"] as? [String] ?? []
        let suggestions = parsed["suggestions"] as? [String] ?? []

        return EvalResult(
            sceneName: context.sceneName,
            passed: passed,
            findings: findings,
            suggestions: suggestions,
            rawResponse: rawText
        )
    }

    /// 从可能包含前后缀文本的字符串中提取第一个 JSON 对象
    private func extractJSON(from text: String) -> [String: Any] {
        let pattern = "\\{[\\s\\S]*\\}"
        guard let range = text.range(of: pattern, options: .regularExpression),
              let data = String(text[range]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    /// 将 CGImage 转为 PNG Data
    private func cgImageToPNGData(_ cgImage: CGImage) -> Data? {
        #if os(macOS)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
        #else
        return UIImage(cgImage: cgImage).pngData()
        #endif
    }
}

// MARK: - 错误类型

public enum VoxAgentEvalError: Error, Sendable {
    case imageEncodingFailed
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    case responseParsingFailed
}

// MARK: - MockAgentEvaluator（测试用）

/// 固定返回预设结果的模拟评估器，用于单元测试
public struct MockAgentEvaluator: AgentEvaluating, Sendable {
    private let result: EvalResult

    public init(result: EvalResult) {
        self.result = result
    }

    /// 便利构造：始终通过
    public static func alwaysPassing() -> MockAgentEvaluator {
        MockAgentEvaluator(result: EvalResult(
            sceneName: "mock",
            passed: true,
            findings: [],
            suggestions: []
        ))
    }

    /// 便利构造：始终失败并带有指定发现
    public static func alwaysFailing(findings: [String]) -> MockAgentEvaluator {
        MockAgentEvaluator(result: EvalResult(
            sceneName: "mock",
            passed: false,
            findings: findings,
            suggestions: ["请修复上述问题"]
        ))
    }

    public func evaluate(screenshot: CGImage, context: EvalContext) async throws -> EvalResult {
        // 使用实际场景名覆盖 mock 中的占位名
        EvalResult(
            sceneName: context.sceneName,
            passed: result.passed,
            findings: result.findings,
            suggestions: result.suggestions,
            rawResponse: result.rawResponse,
            skipReason: result.skipReason
        )
    }
}
