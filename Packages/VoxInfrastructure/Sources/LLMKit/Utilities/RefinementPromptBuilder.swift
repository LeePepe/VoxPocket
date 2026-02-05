import Foundation

public enum RefinementPromptBuilder {
    public static func build(
        text: String,
        customPrompt: String?
    ) -> String {
        let baseInstruction = customPrompt ?? """
        生成优化后的文本：
        1. 保持原意
        2. 添加适当的标点符号
        3. 修正语法错误和口语化表达
        4. 保持语气和风格一致

        只输出优化后的文本。
        """

        return "\(baseInstruction)\n\n原文：\(text)"
    }
}
