import XCTest
import LLMKit

final class RefinementPromptBuilderTests: XCTestCase {
    func testDefaultPromptRequiresSentenceTerminatorWhenMissing() {
        let prompt = RefinementPromptBuilder.build(
            text: "再看一下为什么有时候没有能够成功添加标点符号",
            customPrompt: nil
        )

        XCTAssertTrue(
            prompt.contains("若文本末尾缺少句末标点，必须补充一个句末标点"),
            "默认提示词应明确要求在缺失时必须补句末标点"
        )
    }
}
