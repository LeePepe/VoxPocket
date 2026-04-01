// VoxAgentEvalTests.swift
// VoxAgentEval 模块单元测试
// 测试 EvalReport 模型、MockEvaluator 及集成示例

import XCTest
import CoreGraphics
@testable import VoxAgentEval

// MARK: - EvalContext 测试

final class EvalContextTests: XCTestCase {

    func testBasicInitialization() {
        let ctx = EvalContext(
            sceneName: "录音空闲",
            expectations: ["录音按钮可见", "无错误提示"],
            notes: "首次启动状态"
        )
        XCTAssertEqual(ctx.sceneName, "录音空闲")
        XCTAssertEqual(ctx.expectations.count, 2)
        XCTAssertEqual(ctx.notes, "首次启动状态")
    }

    func testInitializationWithoutNotes() {
        let ctx = EvalContext(sceneName: "录音中", expectations: ["停止按钮可见"])
        XCTAssertNil(ctx.notes)
        XCTAssertEqual(ctx.expectations.first, "停止按钮可见")
    }
}

// MARK: - EvalResult 测试

final class EvalResultTests: XCTestCase {

    func testPassedResult() {
        let result = EvalResult(
            sceneName: "主界面",
            passed: true,
            findings: [],
            suggestions: ["可以进一步优化按钮大小"]
        )
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertNil(result.skipReason)
    }

    func testFailedResult() {
        let result = EvalResult(
            sceneName: "录音中",
            passed: false,
            findings: ["波形动画未显示", "停止按钮颜色异常"],
            suggestions: ["检查录音状态绑定"]
        )
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.findings.count, 2)
        XCTAssertEqual(result.suggestions.count, 1)
    }

    func testSkippedResult() {
        let result = EvalResult.skipped(sceneName: "深度测试", reason: "无 API Key")
        XCTAssertTrue(result.passed, "跳过结果不应算失败")
        XCTAssertEqual(result.skipReason, "无 API Key")
    }

    func testCodableRoundTrip() throws {
        let original = EvalResult(
            sceneName: "编辑器视图",
            passed: false,
            findings: ["文字截断"],
            suggestions: ["增加行高"],
            rawResponse: "{ \"passed\": false }"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EvalResult.self, from: data)

        XCTAssertEqual(decoded.sceneName, original.sceneName)
        XCTAssertEqual(decoded.passed, original.passed)
        XCTAssertEqual(decoded.findings, original.findings)
        XCTAssertEqual(decoded.suggestions, original.suggestions)
    }
}

// MARK: - EvalReport 统计测试

final class EvalReportTests: XCTestCase {

    // MARK: 辅助构造

    private func makeReport(
        passed: Int,
        failed: Int,
        skipped: Int = 0
    ) -> EvalReport {
        var results: [EvalResult] = []

        for i in 0..<passed {
            results.append(EvalResult(
                sceneName: "通过场景\(i)",
                passed: true
            ))
        }
        for i in 0..<failed {
            results.append(EvalResult(
                sceneName: "失败场景\(i)",
                passed: false,
                findings: ["问题\(i)"],
                suggestions: ["修复\(i)"]
            ))
        }
        for i in 0..<skipped {
            results.append(EvalResult.skipped(
                sceneName: "跳过场景\(i)",
                reason: "跳过原因\(i)"
            ))
        }

        return EvalReport(title: "测试报告", results: results)
    }

    // MARK: 统计断言

    func testTotalCount() {
        let report = makeReport(passed: 3, failed: 2, skipped: 1)
        XCTAssertEqual(report.totalCount, 6)
    }

    func testPassedCount() {
        let report = makeReport(passed: 3, failed: 2)
        // 通过=3，跳过也算 passed=true 但 skipped=0
        XCTAssertEqual(report.passedCount, 3)
        XCTAssertEqual(report.failedCount, 2)
    }

    func testSkippedCount() {
        let report = makeReport(passed: 2, failed: 1, skipped: 3)
        XCTAssertEqual(report.skippedCount, 3)
    }

    func testPassRateExcludesSkipped() {
        // 2 通过，1 失败，3 跳过
        // 有效评估 = 3，通过率 = 2/3
        let report = makeReport(passed: 2, failed: 1, skipped: 3)
        XCTAssertEqual(report.passRate, 2.0 / 3.0, accuracy: 0.001)
    }

    func testPassRateAllSkippedReturnsOne() {
        let report = makeReport(passed: 0, failed: 0, skipped: 5)
        XCTAssertEqual(report.passRate, 1.0, accuracy: 0.001)
    }

    func testPassRateAllPassed() {
        let report = makeReport(passed: 4, failed: 0)
        XCTAssertEqual(report.passRate, 1.0, accuracy: 0.001)
    }

    func testPassRateAllFailed() {
        let report = makeReport(passed: 0, failed: 3)
        XCTAssertEqual(report.passRate, 0.0, accuracy: 0.001)
    }

    func testFailuresFilter() {
        let report = makeReport(passed: 2, failed: 3)
        XCTAssertEqual(report.failures.count, 3)
        XCTAssertTrue(report.failures.allSatisfy { !$0.passed })
    }

    func testAllFindingsDeduplication() {
        var results: [EvalResult] = [
            EvalResult(sceneName: "A", passed: false, findings: ["问题X", "问题Y"]),
            EvalResult(sceneName: "B", passed: false, findings: ["问题Y", "问题Z"]),
        ]
        let report = EvalReport(title: "去重测试", results: results)
        // 问题X, 问题Y, 问题Z — 去重后3个
        XCTAssertEqual(report.allFindings.count, 3)
    }

    // MARK: 导出

    func testExportJSON() throws {
        let report = makeReport(passed: 1, failed: 1)
        let data = try report.exportJSON()
        XCTAssertFalse(data.isEmpty)

        // 验证可以反序列化（exportJSON 使用 .iso8601，解码器须保持一致）
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EvalReport.self, from: data)
        XCTAssertEqual(decoded.title, report.title)
        XCTAssertEqual(decoded.totalCount, report.totalCount)
    }

    func testExportText() {
        let report = makeReport(passed: 2, failed: 1)
        let text = report.exportText()

        XCTAssertTrue(text.contains("VoxPocket Agent Evaluation Report"))
        XCTAssertTrue(text.contains("通过率"))
        XCTAssertTrue(text.contains("失败"))
    }

    func testExportTextContainsFailureDetails() {
        let report = makeReport(passed: 0, failed: 1)
        let text = report.exportText()
        XCTAssertTrue(text.contains("问题0"))
    }
}

// MARK: - EvalReport.Builder 测试

final class EvalReportBuilderTests: XCTestCase {

    func testBuilderAccumulatesResults() {
        let builder = EvalReport.Builder(title: "Builder 测试")

        builder.append(EvalResult(sceneName: "场景A", passed: true))
        builder.append(EvalResult(sceneName: "场景B", passed: false))
        builder.append(EvalResult.skipped(sceneName: "场景C", reason: "无环境"))

        let report = builder.build()
        XCTAssertEqual(report.totalCount, 3)
        XCTAssertEqual(report.title, "Builder 测试")
    }

    func testBuilderBuildIsImmutable() {
        let builder = EvalReport.Builder(title: "不变性测试")
        builder.append(EvalResult(sceneName: "A", passed: true))
        let report1 = builder.build()

        builder.append(EvalResult(sceneName: "B", passed: true))
        let report2 = builder.build()

        // 两次 build 结果独立
        XCTAssertEqual(report1.totalCount, 1)
        XCTAssertEqual(report2.totalCount, 2)
    }
}

// MARK: - MockAgentEvaluator 测试

final class MockAgentEvaluatorTests: XCTestCase {

    private func makeMinimalCGImage() -> CGImage {
        let size = CGSize(width: 1, height: 1)
        #if os(macOS)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        return context.makeImage()!
        #else
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in }.cgImage!
        #endif
    }

    func testAlwaysPassingEvaluator() async throws {
        let evaluator = MockAgentEvaluator.alwaysPassing()
        let ctx = EvalContext(sceneName: "单元测试", expectations: ["任何条件"])
        let result = try await evaluator.evaluate(screenshot: makeMinimalCGImage(), context: ctx)

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.sceneName, "单元测试")
    }

    func testAlwaysFailingEvaluator() async throws {
        let evaluator = MockAgentEvaluator.alwaysFailing(findings: ["布局错位", "颜色异常"])
        let ctx = EvalContext(sceneName: "失败场景", expectations: ["按钮可见"])
        let result = try await evaluator.evaluate(screenshot: makeMinimalCGImage(), context: ctx)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.findings.count, 2)
        XCTAssertEqual(result.findings[0], "布局错位")
        XCTAssertEqual(result.sceneName, "失败场景")
    }

    func testEvaluatorOverridesSceneName() async throws {
        let evaluator = MockAgentEvaluator.alwaysPassing()
        let ctx = EvalContext(sceneName: "实际场景名", expectations: [])
        let result = try await evaluator.evaluate(screenshot: makeMinimalCGImage(), context: ctx)

        XCTAssertEqual(result.sceneName, "实际场景名")
    }
}

// MARK: - ClaudeAgentEvaluator 跳过测试（需要 API Key）

final class ClaudeAgentEvaluatorIntegrationTests: XCTestCase {

    private func makeMinimalCGImage() -> CGImage {
        #if os(macOS)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        return context.makeImage()!
        #else
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { _ in }.cgImage!
        #endif
    }

    /// 集成测试：当 API Key 不存在时，评估器应返回跳过结果而非崩溃
    func testSkipsGracefullyWithoutAPIKey() async throws {
        // 确保环境变量未设置（CI 环境预期如此）
        let hasKey = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] != nil
            || ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil

        let evaluator = ClaudeAgentEvaluator()
        let ctx = EvalContext(
            sceneName: "API Key 缺失测试",
            expectations: ["任何条件"]
        )
        let result = try await evaluator.evaluate(screenshot: makeMinimalCGImage(), context: ctx)

        if !hasKey {
            XCTAssertNotNil(result.skipReason, "无 API Key 时应返回跳过原因")
            XCTAssertTrue(result.passed, "跳过不算失败")
        } else {
            // 有 API Key 时的真实调用：仅验证结果结构合法
            XCTAssertFalse(result.sceneName.isEmpty)
        }
    }

    /// 真实 API 调用示例（需要 CLAUDE_API_KEY 环境变量）
    func testRealEvaluation_RequiresAPIKey() async throws {
        guard ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] != nil
                || ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil else {
            throw XCTSkip("需要 CLAUDE_API_KEY 或 ANTHROPIC_API_KEY 环境变量才能运行此测试")
        }

        let evaluator = ClaudeAgentEvaluator()
        let ctx = EvalContext(
            sceneName: "1x1 最小截图",
            expectations: ["这是一个单像素截图，无法评估 VoxPocket UI"],
            notes: "集成测试占位"
        )
        let result = try await evaluator.evaluate(screenshot: makeMinimalCGImage(), context: ctx)

        // 验证响应结构合法（不关心 passed 值）
        XCTAssertFalse(result.sceneName.isEmpty)
        XCTAssertFalse(result.rawResponse.isEmpty)
    }
}
