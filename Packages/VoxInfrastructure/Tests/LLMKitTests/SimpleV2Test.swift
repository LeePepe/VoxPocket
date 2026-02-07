import XCTest
@testable import LLMKit
import Observability

/// 简单的 V2 测试
final class SimpleV2Test: XCTestCase {

    /// 测试 V2 文本完成方法
    func testV2BasicFunctionality() async throws {
        let provider = AppleIntelligenceProviderV2(
            logger: PrintLogger(subsystem: "V2Test", minimumLevel: .info)
        )

        guard provider.isAvailable else {
            throw XCTSkip("Apple Intelligence 不可用")
        }

        let text = "翻译成英语今天是周二"
        print("\n测试文本: \(text)\n")

        // 测试意图分析
        print("【意图分析】")
        let intentStart = ContinuousClock.now
        do {
            let intent = try await provider.analyzeIntent(text, locale: nil)
            let intentDuration = ContinuousClock.now - intentStart
            let intentMs = Double(intentDuration.components.seconds) * 1000 +
                          Double(intentDuration.components.attoseconds) / 1_000_000_000_000_000

            print("✓ 意图: \(intent.intent.rawValue)")
            print("  置信度: \(String(format: "%.2f", intent.confidence))")
            print("  耗时: \(String(format: "%.2f", intentMs))ms\n")

            XCTAssertLessThan(intentMs, 30000, "意图分析应该在 30 秒内完成")
        } catch {
            print("✗ 失败: \(error)\n")
            throw error
        }

        // 测试语气分析
        print("【语气分析】")
        let toneStart = ContinuousClock.now
        do {
            let tone = try await provider.analyzeTone(text, locale: nil)
            let toneDuration = ContinuousClock.now - toneStart
            let toneMs = Double(toneDuration.components.seconds) * 1000 +
                        Double(toneDuration.components.attoseconds) / 1_000_000_000_000_000

            print("✓ 语气: \(tone.tone.rawValue)")
            print("  置信度: \(String(format: "%.2f", tone.confidence))")
            print("  耗时: \(String(format: "%.2f", toneMs))ms\n")

            XCTAssertLessThan(toneMs, 30000, "语气分析应该在 30 秒内完成")
        } catch {
            print("✗ 失败: \(error)\n")
            throw error
        }

        // 测试并行分析
        print("【并行分析】")
        let parallelStart = ContinuousClock.now
        do {
            async let intentResult = provider.analyzeIntent(text, locale: nil)
            async let toneResult = provider.analyzeTone(text, locale: nil)
            let (intent, tone) = try await (intentResult, toneResult)

            let parallelDuration = ContinuousClock.now - parallelStart
            let parallelMs = Double(parallelDuration.components.seconds) * 1000 +
                            Double(parallelDuration.components.attoseconds) / 1_000_000_000_000_000

            print("✓ 意图: \(intent.intent.rawValue), 语气: \(tone.tone.rawValue)")
            print("  总耗时: \(String(format: "%.2f", parallelMs))ms\n")

            XCTAssertLessThan(parallelMs, 40000, "并行分析应该在 40 秒内完成")
        } catch {
            print("✗ 失败: \(error)\n")
            throw error
        }
    }
}
