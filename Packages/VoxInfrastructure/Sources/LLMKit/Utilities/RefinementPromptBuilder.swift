import Foundation

public enum RefinementPromptBuilder {
    public static func build(
        text: String,
        customPrompt: String?
    ) -> String {
        let baseInstruction = customPrompt ?? """
        请对以下语音识别文本进行**最小化修正**：

        修正规则（按优先级排序）：
        1. **保持原意**：绝对不改变用户的表达意图
        2. **添加标点**：在语句结束处添加句号、问号等
        3. **修正错别字**：仅修正明显的同音字错误（如"的地得"）
        4. **保持原句式**：不改变陈述句/疑问句/祈使句的句式
        5. **保留口语风格**：口语化表达是合理的，保持不变

        禁止操作：
        - ❌ 不要改写成书面语或规范表达
        - ❌ 不要添加原文没有的内容
        - ❌ 不要改变句式结构
        - ❌ 不要产生重复内容

        只输出优化后的文本，不要任何解释。
        """

        return "\(baseInstruction)\n\n原文：\(text)"
    }
}
