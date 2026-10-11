# 个人词汇能否影响语音识别

日期：2026-09-13。范围：验证 `multica`、`WebIQ` 这类个人专有名词是否有 ASR 接入口；不实现词库 UI，不录音、不调用收费模型、不构建或安装 App。

## 结论

接口层面可行：当前 Apple Speech 路径有原生 `contextualStrings`；本地 WhisperKit 与云端 Whisper 有 prompt 上下文路径。但这些都是识别偏置，不是强制替换规则。尚未验证在默认 `zh-Hans` 中文夹英文语音中对这两个词的实际改善、精确大小写或误报率。

| 路径 | 官方支持方式 | 本项目现状 / 约束 |
| --- | --- | --- |
| 现有 Apple `SFSpeechRecognizer` | 每次 request 的 `contextualStrings` | 共用 request factory 尚未赋值；这是最轻的试验入口。短词组优先，总数不超过 100。[A1][R1] |
| Apple 自定义语言模型 | `SFCustomLanguageModelData`，词频样例与自定义发音 | iOS 17 / macOS 14 起；准备模型后用于端侧识别，不是服务器识别开关。[A2][A3] |
| 新 `SpeechAnalyzer` + `DictationTranscriber` | `AnalysisContext.contextualStrings`，或 customized-language content hint | iOS / macOS 26 起；官方明确记录该模块的词汇偏置能力。[A4][A5] |
| 新 `SpeechAnalyzer` + `SpeechTranscriber` | 本次未找到官方对该模块消费词汇 context / 自定义模型的承诺 | 不能因为 `AnalysisContext` 有属性就断言新模型支持。不要为热词目的直接迁移到此模块。[A4][A6] |
| 本地 WhisperKit | `DecodingOptions.promptTokens` + `usePrefillPrompt` | 已锁定的 0.16.0 有接口，项目目前未传；累计识别路径还显式关闭 prefill。[W1][W2][R2] |
| 云端 Whisper | audio/transcriptions 的 `prompt` | 现有 multipart 未传；Azure 官方转录接口列出可选 prompt。具体部署仍需验证。[W3][R3] |

## Apple：可以先用现有识别器试

Apple 将 `SFSpeechRecognitionRequest.contextualStrings` 定义为即使不在系统词汇表中也希望识别的词组；文档明确举产品名、领域术语及自造词为用途，措辞是“提高识别概率”。要求尽量每项一两个词、一次不中断地说出，总数不超过 100。API 从 iOS 10 / macOS 10.15 可用，因此本项目 iOS / macOS 26 基线没有系统版本障碍。[A1]

候选接法（仅示意，尚未实现）：

```swift
request.contextualStrings = ["multica", "WebIQ"]
```

项目共用 `DefaultAppleSpeechRequestFactory` 当前设置 partial results、标点以及 `requiresOnDeviceRecognition = false`，没有设置 contextual strings。[R1] `false` 并不等于请求一定上云，只是不要求仅端侧；热词接口文档本身未要求必须端侧。若未来采用自定义语言模型，需另行确认识别器的 `supportsOnDeviceRecognition`，并把请求强制为端侧。[A3][A7]

更重的备选是 `SFCustomLanguageModelData`：可提供带频次的例句和自定义发音，生成/准备模型后通过 request 的 `customizedLanguageModel` 使用。Apple WWDC23 明确说明每份训练数据绑定单个 locale，定制数据不经网络发送，定制识别严格在设备上完成；若不强制 on-device，请求可能不使用定制模型。[A2][A3] 自定义发音使用 X-SAMPA，而且每个 locale 只支持其子集，可用 `supportedPhonemes(locale:)` 查询。[A8] 不能直接把英文音素表当作中文 locale 的发音表。

本次没有找到 Apple 对 `zh-Hans` 中任意英文品牌名、发音变体、驼峰大小写的效果保证。尤其 `WebIQ` 可能被说成 “web eye queue”、`multica` 可能有多种口音；API 可接入不代表这些输入必然正确。先试短词表，再考虑例句/发音定制。

### 新旧 Apple API 不应混淆

Apple 的 `AnalysisContext.contextualStrings` 文档明确以 **DictationTranscriber** 为使用者，并说明生造词可能被估错发音，可通过该模块的自定义语言模型补充发音。总数上限仍是所有 tag 合计 100。[A4] `DictationTranscriber` 文档单列“Improve accuracy”，写明如何用 context 偏置、如何提供词汇；它使用系统听写 / `SFSpeechRecognizer` 端侧同类模型，不支持仅由服务器提供的 locales。[A5]

`SpeechTranscriber` 则是新的通用对话转写模型；其文档要求检查设备和 locale 支持，但本次读取的官方页面没有相同的词汇定制承诺。[A6] 因而本研究只得出“未获官方支持确认”，不是声称永远不支持，也不是已经实测无效。

## Whisper：是上下文提示，不是训练词库

项目锁定 WhisperKit 0.16.0，revision `3199d8f681b648825acc1ed3b056745dcb056c07`。该版本 `DecodingOptions` 提供 `promptTokens`；官方 CLI 将 prompt 文本加前导空格后 tokenize、过滤特殊 token，并开启 `usePrefillPrompt`。该版本 `Constants.maxTokenContext = 224`，解码器将 prompt 限制为 `maxTokenContext / 2 - 1` 即尾部 111 tokens；不能混同云端 Whisper 的 224-token 提示限制。`promptTokens` 不等同于强制前缀 `prefixTokens`。[W1][W2]

项目实时和文件路径尚未传 prompt；累计识别路径显式 `usePrefillPrompt = false`，因此不能只塞 tokens 而不检查该开关。云端路径目前只有音频 multipart，没有 prompt。[R2][R3]

Azure 官方 `2024-10-21` 转录接口列出可选 `prompt`，用于引导风格或延续前段音频，语言应与音频一致。[W3] OpenAI 官方指南展示用 prompt 提示专有名词拼写，`whisper-1` 的提示上限为 224 tokens，并不是通用指令遵循模型。[W4] 中文语音宜测试短中文上下文中包含准确拼写，例如“讨论的产品包括 multica 和 WebIQ”；这是待验证的提示候选，不是效果承诺。

OpenAI 直接服务的 `gpt-4o-transcribe` / mini 支持 prompt；当前指南也记录 `gpt-transcribe` 的 prompt、keywords、languages。但是不能据此假定 Azure 当前部署就是这些模型，或支持同一新增字段。[W4]

混合路径有 Apple 实时、Whisper 最终/合并阶段；后续试验需同时覆盖两个阶段，避免实时正确而最终又覆盖成错误拼写。[R4]

## 最小有效性试验（尚未执行）

建议先不做词库设置页，使用固定的两个词进行 A/B，保持音频、locale、模型、解码配置一致，关闭额外 LLM 精炼，直接比较原始 ASR 输出：

1. 对照组无提示；试验组 Apple contextual strings / Whisper prompt 包含两个词。
2. 每个词准备多句中文夹英文、多个位置和自然读法；包含单词独说与完整句子。
3. 加不含词条的普通中文、发音相近词、静音/噪声作为负例，观察是否凭空插入热词。
4. 分别统计词条命中率、准确拼写及大小写、误插入次数、整体识别质量和延迟；混合模式分别记录实时和最终结果。
5. 仅在真实语音表现有收益后决定持久化词表及 UI。音频、转写、词条不进入日志/遥测；测试内容只保存在应用沙箱。云端试验会把音频及提示词发送到相应供应商，执行前需确认用户授权与目标配置；本地 WhisperKit 不需要这一步外发。

本次仅检查源码、Apple 官方文档/本机 SDK、WhisperKit 源码和供应商 API 文档；没有执行音频识别，因此没有成功率数据。

## 来源

- [A1] Apple：[SFSpeechRecognitionRequest.contextualStrings](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings)。官方 DocC JSON 与本机 Xcode Speech.framework header 均核对。
- [A2] Apple：[SFCustomLanguageModelData](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata)。
- [A3] Apple WWDC23：[Customize on-device speech recognition](https://developer.apple.com/videos/play/wwdc2023/10101/)，尤其 5:53 locale、6:27–6:55 端侧与隐私约束。
- [A4] Apple：[AnalysisContext.contextualStrings](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings)。
- [A5] Apple：[DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber)。
- [A6] Apple：[SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)；[WWDC25 SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)。
- [A7] Apple：[supportsOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)。
- [A8] Apple：[supportedPhonemes(locale:)](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata/supportedphonemes(locale:))。
- [W1] WhisperKit 固定 revision：[Configurations.swift](https://github.com/argmaxinc/WhisperKit/blob/3199d8f681b648825acc1ed3b056745dcb056c07/Sources/WhisperKit/Core/Configurations.swift)、[TranscribeCLI.swift](https://github.com/argmaxinc/WhisperKit/blob/3199d8f681b648825acc1ed3b056745dcb056c07/Sources/WhisperKitCLI/TranscribeCLI.swift)。
- [W2] WhisperKit 固定 revision：[TextDecoder.swift](https://github.com/argmaxinc/WhisperKit/blob/3199d8f681b648825acc1ed3b056745dcb056c07/Sources/WhisperKit/Core/TextDecoder.swift)、[Models.swift](https://github.com/argmaxinc/WhisperKit/blob/3199d8f681b648825acc1ed3b056745dcb056c07/Sources/WhisperKit/Core/Models.swift)。
- [W3] Azure：[OpenAI API reference](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/reference?view=foundry-classic)，audio/transcriptions。
- [W4] OpenAI：[Speech to text guide](https://developers.openai.com/api/docs/guides/speech-to-text/)，prompting。
- [R1] 项目：[DefaultAppleSpeechRequestFactory.swift](../../Packages/VoxInfrastructure/Sources/TranscriptionKit/DefaultAppleSpeechRequestFactory.swift)。
- [R2] 项目：[WhisperKitTranscriber.swift](../../Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift)，实时、累计、文件三种 DecodingOptions。
- [R3] 项目：[WhisperEngine.swift](../../Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperEngine.swift)，multipart 构造。
- [R4] 项目：[TranscriptionMerger.swift](../../Packages/VoxInfrastructure/Sources/TranscriptionKit/TranscriptionMerger.swift)，没有合并器或合并失败时使用 Whisper 结果；[HybridWhisperTranscriber.swift](../../Packages/VoxInfrastructure/Sources/TranscriptionKit/HybridWhisperTranscriber.swift)、[HybridLocalWhisperTranscriber.swift](../../Packages/VoxInfrastructure/Sources/TranscriptionKit/HybridLocalWhisperTranscriber.swift)，实时与最终识别编排。
