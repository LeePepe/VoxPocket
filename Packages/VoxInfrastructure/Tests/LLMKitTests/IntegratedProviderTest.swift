import XCTest
@testable import LLMKit
import LokiKit

/// 测试集成后的 AppleIntelligenceProvider（使用文本完成方法）
final class IntegratedProviderTest: XCTestCase {

    /// 测试集成后的意图和语气分析
    func testIntegratedAnalysis() async throws {
        let provider = AppleIntelligenceProvider(
            logger: PrintLogger(subsystem: "IntegratedTest", minimumLevel: .info)
        )

        guard provider.isAvailable else {
            throw XCTSkip("Apple Intelligence 不可用")
        }

        let text = "Please translate this to English"
        print("\n测试文本: \(text)\n")

        // 测试意图分析
        print("【意图分析】")
        let intentStart = ContinuousClock.now
        do {
            let intent = try await provider.analyze(
                AnalysisRequest(text: text, options: [:], transcriptionMetadata: nil),
                steps: [.intent]
            )
            let intentDuration = ContinuousClock.now - intentStart
            let intentMs = Double(intentDuration.components.seconds) * 1000 +
                          Double(intentDuration.components.attoseconds) / 1_000_000_000_000_000

            if let intentResult = intent.intent {
                print("✓ 意图: \(intentResult.intent.rawValue)")
                print("  置信度: \(String(format: "%.2f", intentResult.confidence))")
                print("  耗时: \(String(format: "%.2f", intentMs))ms\n")

                XCTAssertLessThan(intentMs, 30000, "意图分析应该在 30 秒内完成，实际耗时 \(intentMs)ms")
            } else {
                XCTFail("意图分析返回 nil")
            }
        } catch {
            print("✗ 失败: \(error)\n")
            throw error
        }

        // 测试语气分析
        print("【语气分析】")
        let toneStart = ContinuousClock.now
        do {
            let tone = try await provider.analyze(
                AnalysisRequest(text: text, options: [:], transcriptionMetadata: nil),
                steps: [.tone]
            )
            let toneDuration = ContinuousClock.now - toneStart
            let toneMs = Double(toneDuration.components.seconds) * 1000 +
                        Double(toneDuration.components.attoseconds) / 1_000_000_000_000_000

            if let toneResult = tone.tone {
                print("✓ 语气: \(toneResult.tone.rawValue)")
                print("  置信度: \(String(format: "%.2f", toneResult.confidence))")
                print("  耗时: \(String(format: "%.2f", toneMs))ms\n")

                XCTAssertLessThan(toneMs, 30000, "语气分析应该在 30 秒内完成，实际耗时 \(toneMs)ms")
            } else {
                XCTFail("语气分析返回 nil")
            }
        } catch {
            print("✗ 失败: \(error)\n")
            throw error
        }
    }

    /// 测试完整的 refine 流程（包含并行分析）
    func testCompleteRefinementPipeline() async throws {
        let provider = AppleIntelligenceProvider(
            logger: PrintLogger(subsystem: "IntegratedTest", minimumLevel: .info)
        )

        guard provider.isAvailable else {
            throw XCTSkip("Apple Intelligence 不可用")
        }

        let text = "Please translate this to English"
        print("\n【完整优化流程测试】")
        print("测试文本: \(text)\n")

        let start = ContinuousClock.now

        do {
            let result = try await provider.refine(
                RefinementRequest(text: text, customPrompt: nil, options: [:], transcriptionMetadata: nil)
            )

            let duration = ContinuousClock.now - start
            let ms = Double(duration.components.seconds) * 1000 +
                    Double(duration.components.attoseconds) / 1_000_000_000_000_000

            print("✓ 原文: \(result.originalText)")
            print("✓ 优化: \(result.refinedText)")
            print("✓ 意图: \(result.intentAnalysis.intent.rawValue) (置信度: \(String(format: "%.2f", result.intentAnalysis.confidence)))")
            print("✓ 语气: \(result.toneAnalysis.tone.rawValue) (置信度: \(String(format: "%.2f", result.toneAnalysis.confidence)))")
            print("✓ 总耗时: \(String(format: "%.2f", ms))ms\n")

            // 应该在合理时间内完成（包括分析和优化）
            XCTAssertLessThan(ms, 60000, "完整流程应该在 60 秒内完成，实际耗时 \(ms)ms")

            // 验证意图和语气分析确实运行了
            XCTAssertFalse(result.intentAnalysis.intent.rawValue.isEmpty, "应该能识别出意图")
            XCTAssertGreaterThan(result.intentAnalysis.confidence, 0.0, "意图置信度应该大于 0")
            XCTAssertGreaterThan(result.toneAnalysis.confidence, 0.0, "语气置信度应该大于 0")

        } catch {
            print("✗ 失败: \(error)\n")
            throw error
        }
    }
}
