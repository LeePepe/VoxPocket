import XCTest
import FoundationModels
@testable import LLMKit

/// 测试 Apple Intelligence Guided Generation 的性能问题
///
/// 目标：找出为什么 guided generation 会超时 120+ 秒
final class GuidedGenerationTests: XCTestCase {
    private func requireGuidedGenerationOptIn() throws {
        guard ProcessInfo.processInfo.environment["VOX_RUN_GUIDED_GENERATION_TESTS"] == "1" else {
            throw XCTSkip("Guided generation tests are opt-in. Set VOX_RUN_GUIDED_GENERATION_TESTS=1 to run.")
        }
        guard SystemLanguageModel.default.availability == .available else {
            throw XCTSkip("Apple Intelligence 不可用")
        }
    }

    /// 测试最简单的 guided generation - 只有 2 个字段
    func testMinimalGuidedGeneration() async throws {
        try requireGuidedGenerationOptIn()

        let text = "测试文本"
        let model = SystemLanguageModel(useCase: .contentTagging)
        let instruction = "识别意图"

        print("📝 测试输入:")
        print("  - 文本: \(text)")
        print("  - 指令: \(instruction)")
        print("  - Schema: FastIntentAnalysis (2 fields)")

        let start = ContinuousClock.now
        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: instruction
        )

        var latest: FastIntentAnalysis.PartiallyGenerated?
        var partialCount = 0

        print("\n⏱️ 开始 guided generation...")

        do {
            let stream = session.streamResponse(
                generating: FastIntentAnalysis.self,
                includeSchemaInPrompt: false,
                options: .init(),
                prompt: { Prompt(text) }
            )

            for try await partial in stream {
                latest = partial.content
                partialCount += 1
                print("  ✓ 收到 partial \(partialCount): intent=\(latest?.intent?.rawValue ?? "nil"), confidence=\(latest?.confidence ?? 0)")
            }

            let duration = ContinuousClock.now - start
            let ms = Double(duration.components.seconds) * 1000 +
                     Double(duration.components.attoseconds) / 1_000_000_000_000_000

            print("\n✅ 成功完成!")
            print("  - 耗时: \(String(format: "%.2f", ms))ms")
            print("  - Partial 数量: \(partialCount)")
            print("  - 最终结果: intent=\(latest?.intent?.rawValue ?? "nil"), confidence=\(latest?.confidence ?? 0)")

            // 断言：应该在 5 秒内完成
            XCTAssertLessThan(ms, 5000, "Guided generation 应该在 5 秒内完成，实际耗时 \(ms)ms")

        } catch {
            let duration = ContinuousClock.now - start
            let ms = Double(duration.components.seconds) * 1000 +
                     Double(duration.components.attoseconds) / 1_000_000_000_000_000

            print("\n❌ 失败!")
            print("  - 耗时: \(String(format: "%.2f", ms))ms")
            print("  - 错误: \(error)")
            print("  - 错误类型: \(type(of: error))")

            let nsError = error as NSError
            print("  - Domain: \(nsError.domain)")
            print("  - Code: \(nsError.code)")
            print("  - UserInfo: \(nsError.userInfo)")

            throw error
        }
    }

    /// 测试不使用 guided generation - 直接文本完成
    func testDirectTextCompletion() async throws {
        try requireGuidedGenerationOptIn()

        let text = "测试文本"
        let instruction = "识别这段文本的意图，返回 JSON 格式：{\"intent\": \"plain_content\", \"confidence\": 1.0}"

        print("📝 测试输入:")
        print("  - 文本: \(text)")
        print("  - 指令: \(instruction)")
        print("  - 方法: 直接文本完成（不使用 guided generation）")

        let start = ContinuousClock.now
        let session = LanguageModelSession(
            model: .default,
            tools: [],
            instructions: instruction
        )

        print("\n⏱️ 开始文本完成...")

        do {
            let response = try await session.respond(to: text)
            let duration = ContinuousClock.now - start
            let ms = Double(duration.components.seconds) * 1000 +
                     Double(duration.components.attoseconds) / 1_000_000_000_000_000

            print("\n✅ 成功完成!")
            print("  - 耗时: \(String(format: "%.2f", ms))ms")
            print("  - 响应: \(response.content)")

            // 断言：应该在 5 秒内完成
            XCTAssertLessThan(ms, 5000, "文本完成应该在 5 秒内完成，实际耗时 \(ms)ms")

        } catch {
            let duration = ContinuousClock.now - start
            let ms = Double(duration.components.seconds) * 1000 +
                     Double(duration.components.attoseconds) / 1_000_000_000_000_000

            print("\n❌ 失败!")
            print("  - 耗时: \(String(format: "%.2f", ms))ms")
            print("  - 错误: \(error)")

            throw error
        }
    }

    /// 测试不同的 schema 包含选项
    func testSchemaInclusionVariants() async throws {
        try requireGuidedGenerationOptIn()

        let text = "测试文本"
        let model = SystemLanguageModel(useCase: .contentTagging)
        let instruction = "识别意图"

        // 测试两种 schema 包含选项
        for includeSchema in [true, false] {
            print("\n" + String(repeating: "=", count: 60))
            print("测试 includeSchemaInPrompt = \(includeSchema)")
            print(String(repeating: "=", count: 60))

            let start = ContinuousClock.now
            let session = LanguageModelSession(
                model: model,
                tools: [],
                instructions: instruction
            )

            var partialCount = 0

            do {
                let stream = session.streamResponse(
                    generating: FastIntentAnalysis.self,
                    includeSchemaInPrompt: includeSchema,
                    options: .init(),
                    prompt: { Prompt(text) }
                )

                for try await partial in stream {
                    partialCount += 1
                    if partialCount <= 3 {
                        print("  ✓ Partial \(partialCount)")
                    }
                }

                let duration = ContinuousClock.now - start
                let ms = Double(duration.components.seconds) * 1000 +
                         Double(duration.components.attoseconds) / 1_000_000_000_000_000

                print("✅ 成功: 耗时 \(String(format: "%.2f", ms))ms, \(partialCount) partials")

            } catch {
                let duration = ContinuousClock.now - start
                let ms = Double(duration.components.seconds) * 1000 +
                         Double(duration.components.attoseconds) / 1_000_000_000_000_000

                print("❌ 失败: 耗时 \(String(format: "%.2f", ms))ms")
                print("   错误: \(error)")
            }
        }
    }

    /// 测试不同的模型 use case
    func testDifferentModelUseCases() async throws {
        try requireGuidedGenerationOptIn()

        let text = "测试文本"
        let instruction = "识别意图"

        // 测试不同的 use case
        let useCases: [(String, SystemLanguageModel.UseCase)] = [
            ("contentTagging", .contentTagging),
            // 可能还有其他 use case，但需要查看 API 文档
        ]

        for (name, useCase) in useCases {
            print("\n" + String(repeating: "=", count: 60))
            print("测试 useCase = \(name)")
            print(String(repeating: "=", count: 60))

            let start = ContinuousClock.now
            let model = SystemLanguageModel(useCase: useCase)
            let session = LanguageModelSession(
                model: model,
                tools: [],
                instructions: instruction
            )

            var partialCount = 0

            do {
                let stream = session.streamResponse(
                    generating: FastIntentAnalysis.self,
                    includeSchemaInPrompt: false,
                    options: .init(),
                    prompt: { Prompt(text) }
                )

                for try await _ in stream {
                    partialCount += 1
                }

                let duration = ContinuousClock.now - start
                let ms = Double(duration.components.seconds) * 1000 +
                         Double(duration.components.attoseconds) / 1_000_000_000_000_000

                print("✅ 成功: 耗时 \(String(format: "%.2f", ms))ms, \(partialCount) partials")

            } catch {
                let duration = ContinuousClock.now - start
                let ms = Double(duration.components.seconds) * 1000 +
                         Double(duration.components.attoseconds) / 1_000_000_000_000_000

                print("❌ 失败: 耗时 \(String(format: "%.2f", ms))ms")
                print("   错误: \(error)")
            }
        }
    }
}
