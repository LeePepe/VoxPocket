# VoxPocket：语音识别与文本精炼模型调研

Last-Reviewed: 2026-09-09

范围：面向 macOS / iOS 的中文短句听写、中文夹英文、自动标点及低延迟；核对截至 **2026-09-09** 能访问的官方文档、官方模型卡与实现源码。本文是选型调研，不是准确率实测，也不授权上传录音、下载模型或修改应用。

## 结论

有值得试的新模型，不应只在旧 Apple Speech 和 Whisper 之间选择。

1. **优先验证 Apple 新语音模型**：`SpeechAnalyzer + SpeechTranscriber` 是 iOS / macOS 26 新 API 背后的新一代端侧模型，不是给现有 `SFSpeechRecognizer` 换一个参数。VoxPocket 已要求系统 26+，这是最贴合现有平台、隐私与低延迟目标的候选。
2. **中文云端识别优先试千问；国际 API 增加新一代 OpenAI 和 Gemini 对照**：阿里云当前已列出 `qwen-audio-3.0-asr-flash-streaming`；OpenAI 当前推荐 `gpt-transcribe` / `gpt-live-transcribe`；Google 于 **2026-08-26** 发布了专用 `gemini-3.5-transcribe` / `gemini-3.5-transcribe-live`。不要把通用语音聊天模型当作专用转录模型的同义词。[阿里云](https://help.aliyun.com/zh/model-studio/real-time-speech-recognition) · [OpenAI](https://developers.openai.com/api/docs/guides/speech-to-text) · [Google 发布记录](https://ai.google.dev/gemini-api/docs/changelog)
3. **精炼优先小模型、关闭或降低思考**：保留 Apple Foundation Models 作为本地基线；云端首测 `qwen3.8-flash`（关闭思考）与 `gpt-5.6-luna`（`reasoning.effort: none`），Gemini 采用 `gemini-3.5-flash-lite`（minimal）即可进入对照，不必因为最新是 `gemini-3.8-flash` 就直接选择它。
4. **需要可控的本地替代时，Qwen3-ASR 0.6B / 1.7B 值得做 Mac 原型**，配本地 `Qwen3.5-2B` / `Qwen3.5-4B` 精炼。存在 MLX / Swift 实现，但第三方适配、模型体积、冷启动、内存及流式输入支持都必须验证，不能等同于换一个模型 ID 即可上线。

以上是“最值得评测”的排序，**没有任何候选已被证实能把这次的句号正确改为问号**。

## 1. 现有问题与评测边界

本轮上下文已确认：已安装应用没有拿到远端 Whisper / Azure 精炼所需密钥，精炼选择是 Apple Intelligence；但具体一次精炼是否成功，不能从配置名推断。此前 stdout 指向 `/dev/null`、本地 Loki 不可用，也使历史调用链缺少可回看的证据。

本次另做了不下载模型的只读本机检查：**Apple M5 Pro、48 GiB 内存、macOS 26.6.2**；`SpeechTranscriber.isAvailable == true`，支持列表包含 `zh_CN` / `zh_HK` / `zh_TW`，已安装语言包含 `zh_CN` / `zh_TW`。因此新 Apple ASR 在这台 Mac 上不是纸面候选，具备进入原型评测的条件。

单独用 Swift CLI 查询 `SystemLanguageModel.default.availability` 返回 `unavailable(deviceNotEligible)`。这仅说明**该 CLI 执行上下文**不可用，不能据此断言这台硬件或已安装的 App 无资格使用 Apple Intelligence；需要在 App 内验证同一请求的 availability / 成功状态。

现有快速录音路径还会在文本没有结束标点时补句号。因此评测必须分别观察：

- ASR 临时结果；
- 停录、完成 finalization 后的 ASR 最终结果；
- 精炼实际返回结果，或明确的失败 / 回退；
- 最后写入剪贴板 / 注入目标应用的结果。

“识别内容没有标点 → 最后看到句号”不等于语音模型预测了句号。换模型也不能自动解决提前取临时结果、精炼未实际运行、末尾补句号等应用行为。

本文只保存公开资料和人工构造的评测设计，不收集或记录实际用户录音、转录文本及密钥。实际评测应遵守 [项目隐私红线](../../.specify/memory/constitution.md)：用户内容仅在应用沙箱内，遥测只记时长、模型来源、是否回退等非内容指标。

## 2. 语音识别候选：六组足够覆盖主要路线

| 候选 / 精确名称 | 已核实的能力与新进展 | VoxPocket 适配判断与限制 |
|---|---|---|
| **Apple `SpeechAnalyzer` + `SpeechTranscriber`** | WWDC25 随系统 26 引入；官方称新模型适合实时、长语音及较远距离语音，完全端侧处理，语言资产由系统下载与更新；支持 volatile / final 结果。 | **本地第一优先级**。原生 Swift、无每分钟 API 费。必须运行时查询 `isAvailable`、`supportedLocales` / `supportedLocale(equivalentTo:)`，确认实际设备与中文 locale 支持；不能仅由系统 26+ 推定。停录必须 finalize；不支持时可评估 `DictationTranscriber` / 现有实现回退。官方资料未保证中文问号准确率。[文档](https://developer.apple.com/documentation/speech/speechtranscriber) · [WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/) |
| **阿里云 `qwen-audio-3.0-asr-flash-streaming`**；兼顾 `qwen3-asr-flash-realtime-2026-02-10` | 当前官方实时识别文档已使用 Audio 3.0 Streaming 作为示例；服务说明明确包含带标点文本、普通话与方言、热词 / 上下文增强。新接口支持 WebSocket，也有 AOQ；Qwen3 Realtime 支持 VAD 或客户端 commit 断句。 | **中文云端第一批候选**，北京 / 新加坡服务区域可选；需实际网络和账户验证。不同模型支持项不完全相同：Audio 3.0 有字 / 句时间戳，Qwen3 Realtime 当前没有时间戳。`qwen3-asr-flash-realtime` 稳定别名在文档仍指向 **2025-10-27**，最新列出的快照是 **2026-02-10**，评测应固定快照。Audio 3.0 精确首发日未从本次资料核实，不编造日期。[实时文档](https://help.aliyun.com/zh/model-studio/real-time-speech-recognition) · [当前模型目录](https://help.aliyun.com/zh/model-studio/models) |
| **OpenAI `gpt-transcribe` / `gpt-live-transcribe`** | **2026-07-28 发布**；当前分别推荐用于音频文件 / 已完成语音轮次、真正实时转录；支持提示词、关键词、多语言提示和区域语言标记。实时 API 有 delta / completed 事件及可调延迟策略。 | **国际云端对照**。`gpt-transcribe` 的 `stream=true` 是已提交录音的响应流，不代表实时上传麦克风音频；真正流式要接 `gpt-live-transcribe` 的 WebSocket / WebRTC。新接口用 `languages`，不能无审查复制旧 `language` 参数。实时版本当前不提供词级时间戳、说话人分离及置信度。账户、地区、网络未验证。[发布时间](https://developers.openai.com/api/docs/changelog) · [文件转录](https://developers.openai.com/api/docs/guides/speech-to-text) · [实时转录](https://developers.openai.com/api/docs/guides/realtime-transcription) |
| **Google `gemini-3.5-transcribe` / `gemini-3.5-transcribe-live`** | **2026-08-26 GA**；专用 ASR，支持 85+ 语言、普通话简体中文、自动语种检测和 code-switching；Live 是 WebSocket 双向音频流。支持最多 1,000 个自定义词，官方称通常 ≤100 个效果较好；有 Smart Dictation / Formatting。 | **很新的对照候选**，不同于 Gemini Live 语音对话或通用 Flash 音频理解。Smart 模式会删填充词 / 格式化，评测忠实转录时应单独控制。词级时间戳 / diarization 仅文件版支持，且时间戳会降低准确率、自定义词与这些功能存在互斥。低延迟是厂商能力描述，不是本机实测。[模型卡](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe) · [发布记录](https://ai.google.dev/gemini-api/docs/changelog) |
| **开源 `Qwen/Qwen3-ASR-0.6B` / `Qwen/Qwen3-ASR-1.7B`** | **2026-01-29** 发布；**2026-06-26** 新增原生 Transformers 支持及 `-hf` 变体。30 种语言 + 22 种中文方言；同一模型支持离线 / 流式；Apache-2.0。 | **Mac 端侧第二路线**。官方推理工具以 Python Transformers / vLLM 为主；第三方 `mlx-audio-swift` 已有 0.6B / 1.7B 的 Swift 与量化模型示例。其 `generateStream(audio:)` 示例是在传入音频上流出文本 token，**不能据此认定支持不断追加麦克风音频的真正流式输入**。需分别验证 runtime、量化和 streaming API。官方“并发 128 时 2000 倍吞吐”不等于个人 Mac 的交互速度。[官方仓库](https://github.com/QwenLM/Qwen3-ASR) · [模型卡](https://huggingface.co/Qwen/Qwen3-ASR-0.6B) · [第三方 Swift 实现](https://github.com/Blaizzy/mlx-audio-swift/blob/main/Sources/MLXAudioSTT/Models/Qwen3ASR/README.md) |
| **`FunAudioLLM/Fun-ASR-Nano-2512`** | 800M，支持中 / 英 / 日、中文方言和地区口音，提供 hotwords 与 ITN。另有 `Fun-ASR-MLT-Nano-2512` 的 31 语言版本；不要把多语种版本能力混到 Nano 上。Apache-2.0；当前项目已有 llama.cpp / GGUF 的 macOS 等平台运行路径。 | **中文本地备选，不作为第一轮必测**。官方已有 CPU / 无 Python runtime 路线，但不等于提供经过本项目验证的 iOS SPM 接入。FunASR 流水线可组合 CT-Punc 恢复标点；这是独立组件能力，不能自动算成 ASR checkpoint 的能力。当前 ModelScope / Hugging Face 字符时间戳 checkpoint 状态还存在差异。[仓库与能力边界](https://github.com/FunAudioLLM/Fun-ASR) · [模型卡](https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-2512) |

补充：`SenseVoiceSmall` 仍是值得保留的轻量基线，官方明确其已发布 checkpoint 是普通话、粤语、英语、日语、韩语五种语言，`use_itn` 控制标点与逆文本规范化；不是论文所述 50+ 语言都在 Small 中。它不是本次“新模型优先”首选，也不能由非自回归 / 低延迟自动推断问号更准。[SenseVoice 官方说明](https://github.com/FunAudioLLM/SenseVoice)

### Whisper 生命周期需要区分部署方式

OpenAI 官方弃用页列出：**2026-08-26** 宣布弃用托管 API 的 `whisper-1`、`gpt-4o-transcribe`、`gpt-4o-mini-transcribe`、`gpt-4o-transcribe-diarize`，计划 **2027-02-26** 关闭。因此若新接 OpenAI API，应优先核对新的 `gpt-transcribe` / `gpt-live-transcribe`，不要直接按旧教程接 4o 转录。

这条公告**不等于本地 Whisper 权重失效，也不等于 VoxPocket 的 Azure `whisper` 部署会同日关闭**；Azure 部署生命周期需另查其资源 / 平台公告。[OpenAI 弃用记录](https://developers.openai.com/api/docs/deprecations)

## 3. 文本精炼候选：区分“只修标点”与“润色改写”

| 候选 | 已核实信息 | 本任务建议 |
|---|---|---|
| **Apple Foundation Models，`SystemLanguageModel.default`** | 官方将 refine / edit text 明确列为适用任务，支持原生 Swift 与结构化生成；设备、模型是否下载及区域决定可用性。Apple 当前支持说明列出简 / 繁中文，但要求 Apple Intelligence 兼容设备与可用地区。 | **保留本地基线**。短提示、单一任务、明确输出长度，先验证中文模型实际可用及这次请求有没有成功。不要把系统 Apple Intelligence“已选择”当成功调用。系统模型随 OS 更新，不是可固定一个公开 checkpoint ID 的服务。[能力与 availability](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models) · [设备 / 语言 / 地区，2026-07-07](https://support.apple.com/en-us/121115) |
| **云端 `qwen3.8-flash`**；成本对照 `qwen3.7-flash-2026-07-15` | 阿里云当前模型目录已列出 3.8 Flash；两代均是混合思考，**默认开启思考**，可用 `enable_thinking=false` 关闭；3.7 Flash 可固定 2026-07-15 快照。 | **中文云端首选评测组**，不要沿用旧 `qwen-flash` 的默认行为假设。标点 / 最小精炼关闭思考，低温度，限制输出长度；3.7 Flash 更低的短上下文价格可作为成本对照。版本新不代表中文标点已更好。[模型目录](https://help.aliyun.com/zh/model-studio/models) · [思考控制](https://help.aliyun.com/zh/model-studio/deep-thinking) |
| **OpenAI `gpt-5.6-luna`** | GPT-5.6 家族于 **2026-07-09 发布**，Luna 于 **2026-07-30 降价 80%**；定位低成本、高调用量；官方支持 `none`、`low`、`medium`（默认）等 reasoning effort。 | **国际低成本对照**。只做标点和轻精炼先试 `none`，避免短句也默认花思考时间；不需要为这项任务上更大旗舰。不能仅改现有 Azure deployment 字符串就认定已接到 OpenAI 模型，endpoint / API 格式 / 账户必须匹配。[模型卡](https://developers.openai.com/api/docs/models/gpt-5.6-luna) · [发布与价格调整](https://developers.openai.com/api/docs/changelog) |
| **Google `gemini-3.5-flash-lite`**；质量上界对照 `gemini-3.8-flash` | 3.5 Flash-Lite 于 **2026-07-21 GA**，支持 minimal 思考；最新 3.8 Flash 于 **2026-09-02 GA**，官方侧重复杂软件 / agent 工作流。 | **先 Lite，后按结果决定是否用 3.8**。短文本不用长思考；Latest 别名会变化，评测固定上述 ID 和参数。Gemini 3.8 最新不等于它最适合一两句标点。[模型目录](https://ai.google.dev/gemini-api/docs/models) · [发布时间](https://ai.google.dev/gemini-api/docs/changelog) · [思考配置](https://ai.google.dev/gemini-api/docs/thinking) |
| **本地 `Qwen/Qwen3.5-2B` / `Qwen/Qwen3.5-4B`** | 小尺寸组于 **2026-03-02** 发布；4B 官方卡为 Apache-2.0、多语言模型。MLX Swift LM 已有 Qwen3.5 模型实现。最新更大的 Qwen3.8 开源系列虽已发布，但并非轻量设备的自然替代。 | **离线可控路线**。Mac 先试 4-bit 2B / 4B；权重约为参数量 × 0.5 byte 只是理论下界，运行还需量化元数据、KV cache、激活及其他开销。iPhone 需单独测内存、热量及耗电。现有 Swift 实现不等于 VoxPocket 已集成；当前 MLX 主干的新 FoundationModels bridge 要求 SDK 27，不能直接当系统 26 的现成功能。[发布记录](https://github.com/QwenLM/Qwen3.8) · [4B 模型卡](https://huggingface.co/Qwen/Qwen3.5-4B) · [MLX Swift 实现](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/Models/Qwen35.swift) · [版本边界](https://github.com/ml-explore/mlx-swift-lm) |

Apple 的“支持中文”与“在中国大陆可以使用”是两回事。2026-07-07 官方说明仍列出中国大陆设备 / 账户与所在地限制；本机应通过实际 availability 判断，不能根据时区或语言猜测。Apple Intelligence 的兼容门槛包括 Apple silicon Mac、iPhone 15 Pro 系列 / iPhone 16 系列及以后等；这也**不应反向套用成 SpeechTranscriber 的同一硬件门槛**。[Apple 当前说明](https://support.apple.com/en-us/121115)

## 4. 已核实的价格：只比较同一计费口径

以下为本次查阅时的官方公开按量价格，不含税、汇率、免费额度、批处理折扣、服务器自托管成本或特殊合同；不是用户账户的实际账单。

| 候选 | 公开单价 / 估算 | 依据与边界 |
|---|---|---|
| 阿里云 Audio 3.0 ASR Streaming，北京 | ¥0.00033 / 秒，即 **¥1.188 / 音频小时** | 新加坡为 ¥0.00066 / 秒，即 ¥2.376 / 小时。按输入音频时长收费，输出不另计。[阿里云价格](https://help.aliyun.com/zh/model-studio/model-pricing) |
| OpenAI `gpt-transcribe` | **$0.0045 / 分钟 = $0.27 / 小时** | 文件 / 完成轮次；不与真正实时 API 的价格混为一谈。[模型卡](https://developers.openai.com/api/docs/models/gpt-transcribe) |
| OpenAI `gpt-live-transcribe` | **$0.017 / 分钟 = $1.02 / 小时** | 实时服务。[模型卡](https://developers.openai.com/api/docs/models/gpt-live-transcribe) |
| Gemini 3.5 Transcribe / Live | 官方合计估算分别约 **$0.005 / 分钟**、**$0.009 / 分钟** | 实际按音频输入 / 文本输出 token 计费，估算基于每秒 25 音频 token 和每分钟 175 文本 token；中文文本 token 数可能不同，不能视为固定每分钟单价。[Google 价格](https://ai.google.dev/gemini-api/docs/pricing) |
| `qwen3.8-flash`，北京 | **¥0.8 输入 / ¥2.7 输出，每百万 token** | 页面列 0 < 输入 ≤1M。短句廉价对照 `qwen3.7-flash-2026-07-15` 在 ≤32K 档为 ¥0.2 / ¥0.8。[阿里云价格](https://help.aliyun.com/zh/model-studio/model-pricing) |
| `gpt-5.6-luna` | **$0.20 输入 / $1.20 输出，每百万 token** | 示例 1,000 输入 + 300 输出 token 约 $0.00056；若启用思考、缓存等需按相应计费项计算。[模型卡](https://developers.openai.com/api/docs/models/gpt-5.6-luna) |
| `gemini-3.5-flash-lite` | **$0.30 输入 / $2.50 输出，每百万 token** | 输出包含 thinking token。[Google 价格](https://ai.google.dev/gemini-api/docs/pricing) |
| `gemini-3.8-flash` | 当前 **$0.75 输入 / $3.75 输出，每百万 token** | 这是截至 2026-12-31 的 introductory 价；页面公布 2027-01-01 起 $1.50 / $7.50，不能把促销价写成永久价格。[Google 价格](https://ai.google.dev/gemini-api/docs/pricing) |

端侧模型没有逐次云 API 费，但有下载、内存、功耗和适配成本。对几秒中文听写，等待 final、网络往返、冷启动与精炼输出长度可能比 token 单价更影响体验。

## 5. 问号问题：不能只看 WER / CER 或“有自动标点”

需要把四个不同问题拆开：

1. **是否识别了正确文字**：CER / WER，单独记录规范化策略。
2. **是否正确判断句界和标点**：逗号、句号、问号分别算 precision / recall / F1；尤其同时看“漏问号”和“把陈述句改成问句”。常规去标点 CER / WER 根本测不到这项。
3. **精炼是否忠实原意**：禁止把用户问句当成需要回答的问题，禁止擅自补事实、删否定或改变数字 / 名词。
4. **应用是否保留结果**：模型 final 已有问号时，后续格式化、拼接、注入不可覆盖；没有问号时，也不能只用 `怎么样`、`为什么` 等关键词硬加问号。

例如人工构造的“能不能先检查一下”在不同语境里可以是请求，也可以是询问。文字精炼只看到这串字时，可能已失去原始语调线索。ASR 可以从音频获取韵律信息，但同样没有准确性保证。对于确有歧义的样本，应允许多个合理参考标点，并另保留说话人的意图标签；不要把某个唯一句号 / 问号答案当普遍真值。

精炼应分为两个模式评测，避免用“润色更好”掩盖 ASR 错误：

- **只修标点**：保持字词和顺序，规范中文标点；不确定时保守，不回答内容。
- **轻精炼**：只去明显口头重复与修正语病，保留事实、语气、数字、英文术语；输出原文含义的最小修改版本。

## 6. 建议的最小评测方案

这是后续验证建议，尚未执行，也未上传真实录音。

### 第一轮：先缩小变量，不一次测完所有组合

1. **本地基线**：现有 `SFSpeechRecognizer` 对比 `SpeechTranscriber`；同一批音频，精炼关闭，确认 finalization 完整。
2. **云端 ASR**：加入阿里云 Audio 3.0 Streaming、OpenAI `gpt-transcribe`；若要实时对比，用 `gpt-live-transcribe`，不能拿文件响应流冒充实时。Google Transcribe 作为新模型挑战组，网络 / 区域不合适则不强上。
3. **精炼单独评**：固定同一份 ASR 文本，比较 Apple Foundation Models、Qwen 3.8 Flash 无思考、GPT 5.6 Luna 无思考。Gemini Flash-Lite 做备选，不先做所有 ASR × 所有 LLM 的笛卡尔积。
4. **离线路线第二轮**：如 Apple 仍不达标，再测 Qwen3-ASR 0.6B / 1.7B 的实际 Mac runtime；确定识别收益后才决定是否引入本地 Qwen 精炼模型。

### 样本与指标

- 先人工构造约 30–50 条不含隐私的 3–15 秒短音频，由用户明确授权后录制 / 上传；包括明确疑问、陈述、祈使、间接疑问、中文夹英文、数字、半句停顿、停录前最后一个字等。
- 同一音频 / 同一参考文本、固定模型 ID、语言、热词、VAD 阈值和思考参数。需要主观“说话时快不快”时，再做 live 实验，区别文件批处理。
- 记录：首字延迟、停录到 ASR final 的 p50 / p95、停录到最终粘贴的 p50 / p95、问号 F1、错误改写率、空结果率、失败 / 回退率。
- 本地另测首次模型下载、冷启动、热启动、峰值内存与持续录音功耗；云端另测目标地区网络、超时、鉴权失败、断网回退和真实账单。
- 接受标准应在测试前约定：问号指标改善且不明显增加陈述句误改；最小精炼不得改变含义；延迟容忍阈值由当前实测基线和用户体验共同确定。本文没有捏造毫秒数或提升百分比。

### 可观测性与隐私

实际调用必须记录**真实 provider / model / 是否回退 / 非内容时长指标**，而不是只记录设置中选中的名字。评测内容只在应用沙箱内供人工核查；日志和 Loki 不放音频、逐字转录、prompt 或精炼结果。

云端隐私不能一概而论：Google 价格页区分 free tier 内容可用于改进产品与 paid tier 不用于改进产品；不应用真实私密听写试免费演示。OpenAI 当前数据控制表区分 `/audio/transcriptions`、`/realtime` 与 `/responses`：均默认不训练，但转录、实时和文本端点的保留策略不同，不能笼统称“全部零保留”或“全部保留 30 天”。新 ASR/精炼方案应按实际 endpoint、账户和合约核对。[Google](https://ai.google.dev/gemini-api/docs/pricing) · [OpenAI 数据控制](https://developers.openai.com/api/docs/guides/your-data)

## 7. 未核实事项与决策边界

- 当前云端账号对新模型的实际可调用性，以及手机上的地区 / 设备可用性；本 Mac 的 Apple 新 ASR 可用及部分中文资源已安装已经只读确认，但尚未进行识别试验。
- 各家官方 WER / CER / 吞吐结果使用不同数据、硬件和并发，本报告没有横向拼接成一个排名，也没有据此推断中文问号质量。
- 阿里云 Audio 3.0 Streaming 和 3.8 Flash 的精确公开首发日，本次页面可确认当前已列出 / 可配置，但未确认独立发布时间。
- 新模型在目标硬件上端到端的冷 / 热延迟、内存、耗电、误改率均未实测。
- 本文不更改模型默认值、密钥、日志配置、应用代码、构建产物、安装版本或分支 / PR。下一步应先决定“本地优先”还是“允许云端对照”，并取得测试音频的明确使用授权。
