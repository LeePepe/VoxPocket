import Foundation

public enum RefinementPromptBuilder {
    public static func build(
        text: String,
        customPrompt: String?
    ) -> String {
        let baseInstruction = customPrompt ?? """
        请对以下语音转录文本进行最小化修正：

        修正规则：
        1. **优先保留原文**：若文本已是规范书面语，仅补充缺失的标点，不改变任何措辞
        2. **仅修正明显错误**：只处理同音字错别字（如"的地得"混用）或明显口误，不做风格润色
        3. **保留技术术语和命令**：代码操作、专有名词、指令性短语（如"提交代码"）必须原样保留
        4. **不添加敬语或改变语气**：不将指令句改为请求句，不添加"请"、"麻烦"等词
        5. **添加标点**：仅在完全缺失时补充句末标点

        禁止操作：
        - ❌ 不要改变词语（"提交"不能改为"修改"，"现在的"不能改为"现有的"）
        - ❌ 不要添加原文没有的新内容
        - ❌ 不要删减重要信息
        - ❌ 不要将陈述/指令句改写为请求句式

        只输出修正后的文本，不要任何解释。
        """

        return "\(baseInstruction)\n\n原文：\(text)"
    }
}
