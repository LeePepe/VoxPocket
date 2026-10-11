# Azure 流式 ASR 官方文档核验

核验日期：2026-09-18。范围：Microsoft Learn 一手公开文档及当前资源的只读管理面核验；不含私人端点、凭据、录音或转写内容。不修改 App 或 refine。此记录不是部署成功或性能改善的证明。

## 当前资源只读核验（2026-09-18）

通过固定沙箱配置中的 endpoint/deployment 在进程内定位资源；未输出私有名称或地址，未取 API key。仅对既有个人订阅显式执行 ARM GET/list，未使用工作订阅查询资源，CLI 默认订阅保持不变。

| 检查项 | 管理面实际返回 | 结论边界 |
| --- | --- | --- |
| 已配置资源 | Sweden Central / AIServices；与运行时配置端点唯一匹配 | 确认查询的是当前 App 配置对应资源 |
| 已配置语音 deployment | `gpt-transcribe` / `2026-07-28` / GlobalStandard / Succeeded | 当前仍是已有文件转写路径；未做 WebSocket 推理测试 |
| 实时候选目录 | `gpt-live-transcribe` / `2026-07-28` / GenerallyAvailable；`realtimeTranscription=true`；GlobalStandard | 当前资源目录确实可见，不再仅依赖公开区域表 |
| 实时候选配额 | `OpenAI.GlobalStandard.gpt-live-transcribe`：limit 10、current 0，unit Count | 有可用于部署验证的剩余配额；不等于保证瞬时部署容量，也不是计费报价 |
| 候选 SKU 容量 | default 10、maximum 30000；minimum/step 未返回 | 不推断最小容量为 1；默认容量与当前剩余配额相容 |
| 已有实时 deployment | 本资源没有 `gpt-live-transcribe` 或 `gpt-realtime-whisper` deployment | 要进行真正的实时音频验证，仍需新建获授权的试验部署 |
| 旧实时候选 | `gpt-realtime-whisper` / `2026-05-06`，GA，GlobalStandard；配额 10、已用 0 | 作为备用目录事实，不自动选它替代推荐模型 |

**版本和能力字段有文档漂移：** Azure 公开文档写 `gpt-live-transcribe` 版本 `2026-07-29`，本资源目录实际返回 `2026-07-28`；后续部署应以目标资源接受的版本为准。另，已有 `gpt-transcribe` 目录带 `realtime=true`，而公开 Azure 文档称其不是 Realtime API 模型。该通用 capability 字段不能单独证明它能在长录音尚未 commit 时持续识别；本轮没有连接现有 deployment 去证实或证伪这一点。因此下文关于 offline 的表述是**公开文档结论**，不能覆盖管理面差异。

本轮未创建 deployment、未获取密钥、未建立计费 session、未上传或识别音频。当前验证结论为：**当前资源可进入专用实时模型的部署/音频实验阶段，尚不能宣称实时转写已经跑通或尾延迟已改善。** 下一步需要明确授权新建试验部署及少量非私密合成音频调用；不得顺带修改 App 默认配置或 refine。

## 结论

- **Azure 官方已列出真正的持续音频流转写能力**，不是只有整文件上传后流式返回。模型目录将 `gpt-live-transcribe`（`2026-07-29`）列为实时转写的当前推荐模型；旧 `gpt-realtime-whisper`（`2026-05-06`）仍列在目录中。[1]
- **不能把现有 `gpt-transcribe` 文件部署直接视为实时模型**。Azure 文档明确把它定义为 offline，并明确写出它不是 Realtime API 模型。[1][2]
- **公开支持不等于当前订阅可部署**。WebSocket 文档概述称相关实时模型支持 East US 2 / Sweden Central 的 global deployments；但逐区域矩阵没有 `gpt-live-transcribe` 行，不能据此确认它的完整区域/SKU 可用性或当前账户配额。[3][4]
- 实时路径具备降低“松手后才识别整段”等待的技术条件；**中文准确率、尾延迟和费用尚无此任务的音频实测**，不能承诺优于当前批量路径。[5]

## 模型和区域证据

| 项目 | 文档所证明的内容 | 未证明的内容 |
| --- | --- | --- |
| `gpt-live-transcribe` `2026-07-29` | Azure 模型目录列为实时低延迟转写，且是当前推荐模型；WebSocket 支持列表也列出它。[1][3] | 区域矩阵缺少该行，尚不能确认所有可部署区域、精确 SKU 和账户可用容量。[4] |
| `gpt-realtime-whisper` `2026-05-06` | 概览明确持续 session、音频到达即识别、不等整句话结束；支持 Global Standard、按时长计费。[6] | 目录可见不证明特定账户有配额或该 deployment 已存在。 |
| 旧模型 Global Standard 区域 | 区域矩阵中：Canada Central、Central US、East US 2、France Central、Sweden Central、South India。[4] | 不能把旧模型区域行套给 `gpt-live-transcribe`。 |
| `gpt-transcribe` | `/audio/transcriptions` 离线文件模型；不属于 Realtime API 模型。[1][2] | 没有证据证明同名已有部署能直接换 WebSocket 获得持续流式 ASR。 |

区域矩阵说明 Global 类型推理可以在部署该模型的其他 Azure 区域处理，不能把资源所在区理解成推理数据必定留在该区。[4]

## 接口差异

| 路径 | 输入与触发方式 | 如何判断是否解决目标问题 |
| --- | --- | --- |
| 文件转写 | `/audio/transcriptions`（deployment-style）或 `/openai/v1/audio/transcriptions`，上传完整文件。[2] | 录音结束后才上传整文件仍属于批量输入；不能仅凭响应分块或 `stream=true` 就认定为边录边识别。 |
| 真正实时转写 session | WebSocket `/openai/v1/realtime?intent=transcription`；边录边发送音频块，session 配置为 transcription。[3][5] | 需要在音频尚未送完时收到有效识别结果，并单独测量最后音频送出到最终文字完成的耗时。 |
| 按 turn 提交的实时缓冲 | `input_audio_buffer.append` 不等于已完成一次识别；一般 turn 流程可由 VAD 或客户端 `input_audio_buffer.commit` 提交。[5] | 不应只在整个长录音结束时才 commit，再把“连接一直开着”算作已验证持续识别。也不能据此推断 Azure 的 `gpt-transcribe` 支持此模式。 |

Azure WebSocket 专用转写示例使用：[3]

- GA 路径 `/openai/v1/realtime?intent=transcription`，不是 preview 的 `/openai/realtime?api-version=...&deployment=...`。
- `session.update` → `session.type = "transcription"`。
- `session.audio.input.format = {"type":"audio/pcm","rate":24000}`；示例是单声道 `int16`、100ms 音频块。
- `session.audio.input.transcription.model` 使用**已部署名称**，不是假定模型 ID 可直接代替部署名；Azure API reference 明确要求 deployment name。[7]
- `session.audio.input.transcription.language` 可给语言提示；`delay` 示例列出 `minimal / low / medium / high / xhigh`。
- `input_audio_buffer.append` 发送 Base64 PCM；示例还定期发送 `input_audio_buffer.commit`。
- 接收示例处理 `conversation.item.input_audio_transcription.completed`、`response.text.done` 与转写失败事件。

这些是官方示例形状，不是已经对目标部署验证过的最小完整协议。实际验证还需确认 `session.updated` 接受模型/参数、音频结束前的有效结果以及末段 flush/完成语义；仅成功握手或空 session 不构成音频识别成功。

## 文档不一致与验证边界

1. WebSocket 的 dedicated transcription 代码仍标作 `gpt-realtime-whisper`，但同页 supported models 和主概览明确列出 `gpt-live-transcribe`；主概览也说明可替换 deployment 使用相同 quickstart。[3][5] 这是可试验的官方路径，不是两个模型所有参数/事件行为都已实证相同。
2. WebSocket 示例 API-key 版本每 3 秒 commit，Entra 版本每 3 个 100ms 块 commit；这属于示例差异，不应视为服务协议的强制切块频率。[3]
3. transcription overview 的新段落明确支持实时模型，但后面的旧场景对比表仍出现 OpenAI 实时转写 “Not available”；模型目录、实时概览、WebSocket 支持列表更具体且相互印证。[1][2][3][5]
4. `gpt-live-transcribe` 的区域/SKU 需结合实际资源模型目录、部署目录与配额确认；本记录不查询账户，也不新建 deployment。
5. 文档中的语言提示为 ISO-639-1；中文候选提示为 `zh`，不是直接照抄 App locale `zh-Hans`。语言准确率仍需生产相近的音频验证。[5][6]
6. 没有使用 OpenAI 直连文档来代替 Azure 支持证明；也没有把旧基准的纯文件转写耗时套用到实时路径。

## 实际获取的一手来源

以下页面于核验日期通过 HTTPS GET 获取 Microsoft Learn Markdown（URL 加 `accept=text/markdown`），结论来自正文而非搜索摘要：

1. [Foundry Models sold by Azure — Audio models](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure#audio-models)：模型 ID、版本、推荐状态、duration billing、offline 边界。
2. [Transcription models from OpenAI](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/transcribe-overview)：文件/实时工作流与接口路径。
3. [Use the GPT Realtime API via WebSockets](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/realtime-audio-websockets)：支持列表、连接格式和 dedicated transcription 示例。
4. [Region availability for Foundry Models sold by Azure](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability?pivots=standard)：Global Standard 区域行和数据处理位置边界。
5. [Use the GPT Realtime API for speech and audio](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/realtime-audio)：模型、session 类型、GA API、语言提示、turn/VAD 机制。
6. [GPT Realtime Transcribe overview](https://learn.microsoft.com/en-us/azure/foundry/openai/concepts/gpt-realtime-whisper)：持续识别定义、旧模型 deployment 类型。
7. [Realtime API reference](https://learn.microsoft.com/en-us/azure/foundry/openai/realtime-audio-reference)：Azure transcription model 字段必须使用 deployment name 的差异说明。
