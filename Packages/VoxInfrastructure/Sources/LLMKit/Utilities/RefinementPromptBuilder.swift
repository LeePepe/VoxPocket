import Foundation

public enum RefinementPromptBuilder {
    public static func build(
        text: String,
        customPrompt: String?
    ) -> String {
        let baseInstruction = customPrompt ?? """
        请将以下语音转录文本改写为准确、自然的书面文字表达：

        改写规则：
        1. **口语转书面**：将口语化、碎片化的表达转为流畅的书面语
        2. **保持原意**：不改变用户想表达的核心内容和意图
        3. **添加标点**：在适当位置添加句号、逗号、问号等标点
        4. **修正错别字**：修正同音字错误（如"的地得"）和明显笔误
        5. **整理语序**：修正因口误导致的语序混乱，使表达更清晰

        禁止操作：
        - ❌ 不要添加原文没有的新内容或观点
        - ❌ 不要删减重要信息
        - ❌ 不要产生重复内容

        只输出改写后的文本，不要任何解释。
        """

        return "\(baseInstruction)\n\n原文：\(text)"
    }
}
