# VoxKit 拆分：语音 SDK 独立 + VoxPocket 只保留 App

- 状态：Draft（Owner 审阅中，`owner-review`）；plan §12 Q1–Q10 已由 Owner 决定（2026-09-24）
- 日期：2026-09-24
- 需求来源：Owner 的 VoxKit 拆分需求稿（未入库）；Owner 决策来自 Owner 的仓库治理计划（不在本仓），相关条目摘录在本文 §2，以本文为准
- 配套：[`plan.md`](./plan.md)（分阶段计划与 Plan-Review 记录）· [`tasks.md`](./tasks.md)（依赖顺序任务）· [`research.md`](./research.md)（引擎选型与代码现状调研）
- 本 PR 只含 spec/plan，不含产品代码。

## 1. 目标

把语音能力抽成独立 SwiftPM SDK **VoxKit**（公开 repo `LeePepe/VoxKit`，许可证沿用 VoxPocket 的 MIT），提供：

- 多种语音识别（SR）：Apple Speech / Azure 整段转写（batch）/ Azure 实时（realtime）/ 本地 WhisperKit / Hybrid 双路；**麦克风采集在 SDK 内**
- 多种 LLM：Apple Intelligence / Azure Foundry，可扩展
- refine 策略：`RefinementType`、prompt 构建、意图/语气分析、双路转写合并
- 可组合 workflow，三种编写方式编译为同一 `WorkflowDefinition`：Swift DSL（result builder）/ Codable JSON（节点以 registry id 引用）/ preset + overrides
- 平台：macOS 26+ 与 iOS 26+（两平台 CI build/test）

VoxPocket 只保留 UI、编辑器领域、持久化、平台适配，经 VoxKit 使用语音能力。

## 2. Owner 已定（2026-09-24）

| # | 决策 |
|---|---|
| D1 | 名称 VoxKit；公开；许可证同 VoxPocket（MIT） |
| D2 | 麦克风采集放进 SDK |
| D3 | SDK 同时支持 macOS 与 iOS；App 删除「iOS 暂停」状态。iOS 只做 CI build/test；iOS TestFlight 需另行授权 |
| D4 | 阶段 1–3 在本仓完成，再拆 repo（阶段 4） |
| D5 | 阶段 5（设置页 workflow 编辑 UI）不在范围，见 backlog #53 |
| D6 | 拆仓前对 filter-repo 导出历史做隐私预检 |
| D7 | iOS build/test 先作非 required lane；阶段 1 修绿 SDK iOS 后改 required |
| D8 | plan §12 Q1–Q10 已定；其中 Q2（Owner 修改）：个人信息从导出历史删除；非公开项目信息（Azure 主机名、内部 endpoint/配置、内部 issue 号）不进 git，用 gitignore 的本地文件 + 提交 `.example` 模板，VoxPocket 与 VoxKit 同样适用 |
| D9 | App 与 VoxKit 都做 iOS build/test（App 单元测试也在 iOS Simulator 上运行，Q6） |

## 3. 既有行为（Existing behaviour，基线 = `origin/main` @ `afec620`）

以下行为在阶段 1–2 **逐字保留**，阶段 3 由 golden test 证明等价。每条后标注负责的代码位置。

### 3.1 转写

- **EB-1 转写器选择**：`LLMAppConfig.defaultTranscriberProvider = .hybridWhisper`。macOS 由 `StageModelRouting.makeTranscriber` 包成 `DefaultSelectableTranscriptionCoordinator`；**每次录音开始**时读 `StageModelSettings`，调用 `beforeSession` 回调（同步配置文本模型服务），再按下表选转写器（`StageModelRouting.resolveTranscriber` / `resolvedSpeechModel`）：

  | `settings.speech` | batch 配置 | realtime 配置 | 实际转写器 |
  |---|---|---|---|
  | `.appleSpeech` | 任意 | 任意 | `AppleSpeechTranscriber` |
  | `.batch` / `.realtime` | 缺失 | 任意 | `AppleSpeechTranscriber` |
  | `.batch` | 有 | 任意 | `HybridWhisperTranscriber(realtimeConfig: nil)` |
  | `.realtime` | 有 | 缺失 | `HybridWhisperTranscriber(realtimeConfig: nil)`（降为 batch） |
  | `.realtime` | 有 | 有 | `HybridWhisperTranscriber(realtimeConfig: …)` |

  iOS（App 壳 `ServiceContainer.makeTranscriber` 的 `#else` 分支）：`realtimeTranscriptionConfig` 恒为 nil；batch 配置齐全用 `HybridWhisperTranscriber(realtimeConfig: nil)`，否则 `AppleSpeechTranscriber` 并打 warning（`Azure transcription configuration missing; actual_provider=appleSpeech`）。其余 `TranscriberProvider` 分支（`localWhisperKit` 走 `LoadingFallbackTranscriptionCoordinator(primary: WhisperKit, fallback: AppleSpeech)`，`hybridLocalWhisper`，`azureWhisper`，`appleSpeech`）代码保留，当前默认不走。
- **EB-2 Hybrid（Azure）**：`MicrophoneRecorder` 采集，buffer 同时喂 Apple Speech 与 WAV 文件；Apple Speech partial 驱动实时文本与自动停止；realtime 会话在录音期间发送音频，`finish()` 失败时回退 `WhisperEngine` 整段转写（`RealtimeASRFinalizer`）；`shouldFinalize` 为假（无 realtime 且 Apple/云端都无文本）时跳过云端调用并删除音频；终稿只 `finalResultPublisher` 发送一次；未使用合并器时 live 也同步发送终稿。
- **EB-3 合并器注入**：`ServiceContainer.injectMergerIfNeeded` 对 `HybridWhisperTranscriber` **不注入**；对其他 `MultiRecognizerTranscriber`（`HybridLocalWhisperTranscriber`）注入 `LLMTranscriptionMerger`。`mergedTranscription` 规则：合并器为空、Apple 文本为空、或两路相同 → 直接用 Whisper；合并器抛错 → Whisper；输出长度 > 较长输入 × 1.5 → Whisper。
- **EB-4 两套独立栈**（macOS）：主编辑器与快捷录音各自一套转写器 / 文本模型服务 / UseCase，互不污染；本地 Whisper engine 底层共享（`SharedLocalWhisperEnginePool`）。
- **EB-5 临时音频与模型缓存**：录音 WAV 暂存 `Application Support/VoxPocket/TemporaryAudio/`，目录 0700、排除备份，终稿后删除；WhisperKit 模型下载到 `Caches/VoxPocketWhisperKitHub`；模型快照损坏时，`resetCorruptedCache` 还会删除 HuggingFace 缓存候选目录（`Caches/huggingface/hub/models--argmaxinc--whisperkit-coreml`，macOS 另加 `~/.cache/huggingface/hub/…`）。
- **EB-6 权限**：macOS `AVCaptureDevice.requestAccess(.audio)`；iOS `AVAudioSession` `.record/.measurement/.duckOthers` 并 `setActive(true)`；Speech 授权由 `SFSpeechRecognizer.requestAuthorization`。默认识别语言 `zh-Hans`。

### 3.2 文本模型与精炼

- **EB-7 文本模型服务**：macOS 每个入口一个 `DefaultStageTextModelService`，每次录音 `configure(settings)` 新建 `DefaultLLMService`，不改正在精炼的实例；`settings.refinement == .azureFoundry` 且 Azure 不可用 → 精炼请求明确失败（`ConfigurationError.unavailable`，文案「所选文本模型尚未配置，请检查语音与文本设置。」），**不偷偷改用 Apple**；语音采集不受影响。iOS 用单个 `DefaultLLMService`：精炼 provider 初始为 `LLMAppConfig.defaultProvider`（`azureFoundry`），偏好 `llm.provider` 有合法存值时切换为该值，存值非法或被删除时保持当前 provider；intent 与 tone **固定**路由到 `appleIntelligence`（`LLMAppConfig.analysisProviderOverrides`），entities/tags/params 用当前精炼 provider（macOS 则跟随 `settings.intent`）；`llmSkipContentAnalysis` → `setSkipContentAnalysis`；`llmProviderDidChange` / `llmAnalysisSettingsDidChange` 通知时重新应用。
- **EB-8 分析路由**：`StageModelRouting.analysisOptions` 把 intent（含 entities/tags/params）路由到 `settings.intent`，tone 路由到 `settings.tone`；`DefaultLLMService.analyzeContent` 按 provider 分组，同一 provider 内**先 intent 组后 tone 组顺序执行**；**不同 provider 组之间的顺序不确定**（遍历 `Dictionary`，每进程哈希种子不同）；某步失败或 provider 缺失 → 该步用默认值并记入 `missingAnalysisSteps`，不阻断精炼。
- **EB-9 跳过分析**：`skipAnalysis == true` → 不调用任何分析，`missingAnalysisSteps = 全部`。
- **EB-10 精炼 prompt**：`RefinementPromptBuilder.build(text:customPrompt:)` 的默认指令逐字固定；`refine` 用 `complete`，`refineStreaming` 先（非跳过时）等待分析结束再流式输出 chunk；Apple / Azure provider 自身的 `refine*` 也用同一 builder。
- **EB-11 Azure 请求形状**：`AzureFoundryProvider` 的 URL、头、body（`AzureFoundryProviderRequestTests` 覆盖）不变；缺配置时 `makeAzureFoundryConfig` 仍构造无 key 的 config，使 Azure「不可用」而非消失。

### 3.3 配置、日志、遥测

- **EB-12 凭据**：只有 App 壳读取 env 与沙箱 `config.private.json`（`LLMAppConfig.loadRuntimeConfiguration` → `DefaultPrivateModelConfigurationLoader`），以值传入 `AzureWhisperConfig` / `AzureRealtimeTranscriptionConfig` / `LLMProviderConfig`。TranscriptionKit/LLMKit 源码当前**无** env 读取（已核查）。
- **EB-13 日志**：TranscriptionKit/LLMKit 直接用 LokiKit `Logger`/`PrintLogger`；上传到 Loki 的只有 `VoxPocketLogging.allowedMessages` 精确匹配的消息与 `allowedContextKeys` 字段，其余被替换。
- **EB-14 遥测**：事件名来自 LokiKit `TelemetryEventName`；UseCase 层发 `recording.*`、`transcription.completed`、`refinement.completed/failed`、`session.*`；WhisperKit 发 `whisper.model.loaded/load_failed`、`transcription.completed/failed`。
- **EB-15 错误**：SDK 候选代码抛 `VoxDomain.CoreModels.VoxError` 的 `llm*`、`microphoneAccessDenied`、`speechRecognitionUnavailable` 等 case，用户可见文案来自其 `errorDescription`。

### 3.4 已知问题（本 spec 修正，见 §6）

- **KI-1**：`LLMTranscriptionMerger` 把两路转写、prompt、LLM 输出写进 info/warning 日志（5 处）；`LocalWhisperRawOutputLogger` 把 Whisper 原始输出写进 debug 日志，且有测试断言这一行为。两者违反宪法 IV。
- **KI-2**：WhisperKit 遥测带 `"reason": String(describing: error)` 自由文本，不属于宪法 IV 允许的指标。
- **KI-3**：`AzureFoundryProviderRequestTests` 使用看似真实的 Azure 资源主机名（宪法 V：不得提交 Azure 资源标识）。
- **KI-4**：SDK 候选代码内有产品名硬编码路径（`VoxPocket/TemporaryAudio`、`VoxPocketWhisperKitHub`）。

## 4. 用户故事与验收标准

AC 编号稳定，plan/tasks/测试名引用它们；只可追加，不重编号。

### US1 — 迁移期间用户体验不变（P1）

作为 VoxPocket 用户，我在整个迁移期间录音、转写、精炼、快捷录音与设置的行为与今天完全一样。

- **US1-AC1**：阶段 1 最先三个 commit（零行为变化的注入接缝 + 基线录制，plan §3.1 1.0a–1.0c、§3.4）得到 golden trace；阶段 1、2、3 合并前，相同矩阵的 trace 与基线按 plan §3.4 的比较规则相等：转写事件序列、每个 provider 收到的 prompt 原文、每步分析选用的 provider、`RefinementResponse` 字段、`missingAnalysisSteps`、遥测事件名与属性键逐项相等；跨 provider 的分析组顺序（今天即不确定）从基线起按 (provider, 步骤) 归一；阶段 3 起同层分析调用顺序按 RB-12 归一。
- **US1-AC2**：现有 SPM 与 App 测试全部通过；除 §6 列出并获 Owner 批准的项外，不删除、不跳过、不放宽任何断言。
- **US1-AC3**：`StageModelSettings` 的持久化键（`model.speech`/`model.intent`/`model.tone`/`llm.provider`/`llm.skipContentAnalysis`/`model.realtimeDeployment`）、默认值与「下一次录音生效，进行中不切换」语义不变（EB-1、EB-7）。
- **US1-AC4**：主编辑器与快捷录音栈仍相互隔离（EB-4）；有测试证明两个栈的 workflow 运行实例不共享可变状态（有意共享的本地 Whisper engine pool 除外）。
- **US1-AC5**：`VoxPocketLogging.allowedMessages` 中现有的精确消息仍以相同文本产生；遥测事件名和属性键集合不变（KI-2 的 `reason` 键按 §6 替换为 `error_kind`）。
- **US1-AC6**：用户可见错误文案（`errorDescription`、`ConfigurationError`）逐字不变。
- **US1-AC7**：Azure 精炼未配置时仍明确失败，不静默改用 Apple（EB-7）。

### US2 — 宿主以远程 SPM 依赖接入 SDK（P1）

作为宿主 App 开发者（VoxPocket 或未来的其他 App），我用 exact 版本依赖 VoxKit，注入凭据、日志、遥测与存储位置，通过 async API 使用语音能力。

- **US2-AC1**：`ai/INTEGRATION.md` 中的最小消费者 fixture 只用 public API，在 macOS 与 iOS Simulator 上 `swift build`/`xcodebuild build` 通过（外部消费者验证，W5）。
- **US2-AC2**：凭据只经 `CredentialProvider` 获取；SDK 源码中无 env / 配置文件 / UserDefaults / Bundle / Keychain 读取（红线 R1 机械检查通过）。
- **US2-AC3**：日志与遥测只经 `VoxLogger` / `VoxTelemetry` 协议；VoxKit 的依赖闭包中无 LokiKit / shared-telemetry（R2）。
- **US2-AC4**：public API 只用 async/await、`AsyncStream`/`AsyncThrowingStream`，无 Combine 类型与回调式 completion 参数（R4）。
- **US2-AC5**：只依赖 `VoxSpeech` 的消费者不编译、不链接 WhisperKit；WhisperKit 只随 `VoxSpeechWhisperKit` product 引入（SPM 仍会解析该包，见 research R-3）。
- **US2-AC6**：临时音频与模型缓存目录由宿主经 `VoxStorageLocations` 提供；SDK 不含任何产品名路径（KI-4）。

### US3 — 可组合 workflow（P1）

作为宿主开发者，我用 DSL、JSON 或 preset + overrides 定义流程，三者编译为同一 `WorkflowDefinition` 并由同一引擎执行。

- **US3-AC0**：workflow 有 `speech`（采集→转写→[合并]→终稿）与 `refine`（文本 + 自定义 prompt + 元数据→分析→精炼流式输出）两个入口；一个 preset 同时定义两者；阶段 3 后 App 的精炼只经 `refine` 入口。
- **US3-AC1**：同一流程用三种方式编写，得到的 `WorkflowDefinition` `==` 相等；JSON 编码→解码往返无损。
- **US3-AC2**：校验在执行前完成：未注册的节点 id、悬空引用、环、输入输出类型不匹配 → 抛 `WorkflowValidationError`（带节点 id，不带用户内容）。
- **US3-AC3**：`StageModelSettings` 的每一种取值组合映射为 `Preset.default.overriding(...)`，其运行 trace 与 US1-AC1 基线相等。
- **US3-AC4**：同一层级无依赖的节点（如 intent ∥ tone）并发执行；有测试用可控时钟证明并发，且合并结果与顺序执行一致。
- **US3-AC5**：取消（宿主取消 Task 或停止录音）传播到所有运行中节点：在运行的事件流结束之前，每个运行中节点都观察到取消，且无残留子 Task（测试断言）。
- **US3-AC6**：节点失败策略（`fail` / `fallback(node)` / `default(value)`）能复现 EB-2 的 realtime→batch 回退、EB-3 的合并回退、EB-8 的分析默认值。
- **US3-AC7**：内置 preset 至少覆盖：`hybrid.azure`（realtime/batch）、`apple.speech`、`local.whisperkit`、`hybrid.local`，以及分析/精炼的全部 provider 组合。

### US4 — SDK 红线可机械检查（P1）

作为维护者，我能在 CI 上看到 SDK 红线被检查，违规 PR 被拦截。

- **US4-AC1**：R1（无 env/文件/配置读取）、R2（无 LokiKit/shared-telemetry 依赖）、R3（日志/遥测无转写、音频、精炼文本）、R4（async public API）、R5（无产品标识与 Azure 资源标识）各有一个检查；每个检查都有**负例 fixture** 证明它会失败。
- **US4-AC2**：R3 同时以类型约束实现（日志消息为 `StaticString`，字段只允许数值/时长/布尔/枚举标签），并有隐私金丝雀测试：所有 preset 用含金丝雀串的假数据运行，日志、遥测、SDK 抛出的错误描述中都找不到金丝雀串。
- **US4-AC3**：检查脚本位于 `Packages/VoxKit/` 内，随拆仓一起迁移；拆仓前在 VoxPocket CI、拆仓后在 VoxKit CI 执行。
- **US4-AC4**：`@unchecked Sendable` 与 `nonisolated(unsafe)` 在 SDK 内每处都有理由注释，数量不超过阶段 1 开工时的基线（宪法 III）。

### US5 — iOS 可构建可测试（P2）

作为维护者，我在 CI 上看到 SDK 与 App 的 iOS 构建/测试结果；iOS TestFlight 不在范围。

- **US5-AC1**：SDK 代码（`Packages/VoxKit` 与阶段 1–2 期间仍在 VoxInfrastructure 的两个 kit 及 `VoxKitBridge`）在 iOS Simulator 上 build + test 通过；PR-1 合并后该 lane 由非 required 改为 required（ruleset 变更经 Owner 批准）。
- **US5-AC2**：iOS 采集：请求录音权限、设置并在停止/中断时释放 `AVAudioSession`、处理中断与路由变化通知；模拟器测试以注入的合成音频源运行，不依赖真实麦克风。
- **US5-AC3**：App iOS target 继续 CI 构建通过，`VoxPocketTests` 在 iOS Simulator 上运行通过（Owner Q6）；AGENTS/constitution 中不再有「iOS 暂停」表述（S3 完成，只核对）。
- **US5-AC4**：不触发 iOS TestFlight；`testflight.yml` 的 iOS 路径不改。

### US6 — 拆出独立 repo 并由 App 远程依赖（P1）

- **US6-AC1**：新 repo 历史由 `git filter-repo` 从 VoxPocket 导出，包含 TranscriptionKit/LLMKit 迁入前后的提交；导出树与 `main:Packages/VoxKit` 一致；在 `main` 上与导出 repo 中抽查的文件 `git log --follow` 都能追溯到阶段 1 之前的提交。
- **US6-AC2**：导出历史中不含个人信息（作者/提交者/trailer 邮箱统一为 noreply）与非公开项目信息（Azure 资源主机名、内部 endpoint/配置、内部 issue 号）：由 filter-repo 的 `--mailmap`/`--replace-text`/`--replace-message` 处置；推送前隐私预检（凭据、私有配置文件名、身份模式、Azure 资源标识、个人邮箱与内部 issue 号）在处置后的历史上结果为零发现（Owner Q2）。
- **US6-AC3**：新 repo 满足 shared-ci repo 合同 v1 的 8 项（`audit` 零发现），`quality / aggregate` 与 `codex-review-target / codex-review` 为 required，含 macOS 与 iOS lane。
- **US6-AC4**：首个版本 tag 随源码发布 `ai/`（README/USAGE/INTEGRATION/EXAMPLES/COMPATIBILITY/MIGRATION/registry.json）；外部消费者按 exact 版本验证通过。
- **US6-AC5**：VoxPocket 改为 `.package(url:…, exact: <tag>)`，删除 `Packages/VoxKit`，`Package.resolved` 入库，AGENTS 依赖段写明版本与 `ai/` 链接；全部既有测试与 golden trace 仍通过。
- **US6-AC6**：回滚路径：revert adopt PR 即恢复 path 依赖并通过 CI（在 adopt PR 上演练一次 revert 的 CI）。
- **US6-AC7**：VoxKit 与 VoxPocket 的非公开配置只存在于 gitignore 的本地文件，仓内只有 `.example` 模板；`LeePepe/VoxKit` 的 tag 受保护（不可删除、不可移动）。

### US7 — 治理文档同步（P2）

- **US7-AC1**：宪法按 Governance 流程修订（规则、理由、迁移影响、版本号），与受影响 layer 的 `red_lines` 同一变更提交。
- **US7-AC2**：根 tech-context、`dependency-graph.md`、`packages-architecture.md`、`AGENTS.md` layer 表、各层 `tech-context.md` 与代码一致，`check_frontmatter.py`（或 shared-ci `audit`）通过。

## 5. 兼容性（Compatibility）

| 面 | 结论 |
|---|---|
| 用户数据 | 无迁移。SwiftData 会话、`UserDefaults` 偏好键（`model.speech`、`model.intent`、`model.tone`、`llm.provider`〔iOS 与 macOS 精炼共用〕、`llm.skipContentAnalysis`、`model.realtimeDeployment`）不变。 |
| 私密配置 | `config.private.json` 与 env 变量名、校验、位置不变；仍只由 App 读取。 |
| 临时文件位置 | 路径值不变（App 通过 `VoxStorageLocations` 传入与今天相同的目录）；只是选择权从 SDK 移到 App。 |
| 日志 | Loki 允许名单内的消息逐字保留；控制台（本机）上带插值的非允许名单日志改为「静态消息 + 数值字段」格式。 |
| 遥测 | 事件名不变；WhisperKit 的 `reason` 自由文本 → `error_kind` 枚举标签（KI-2）。 |
| App 内部 API | 属于 App 内部，不对外承诺：模块名 `TranscriptionKit`/`LLMKit` → `VoxCore`/`VoxSpeech`/`VoxSpeechWhisperKit`/`VoxRefine`/`VoxLLM`/`VoxWorkflow`/`VoxWorkflowWhisperKit`（plan §2.1）；Combine 形状的 `TranscriptionCoordinator` 等协议移到 App 侧桥接 target `VoxKitBridge`，签名不变（plan §2.2）。 |
| 错误类型 | SDK 抛 `VoxKitError`（替代 `VoxError` 的对应 case），`errorDescription` 逐字相同；`VoxError` 其余 case 留在 VoxDomain。 |
| 构建 | 阶段 1–3：`Packages/VoxKit` 为本地 path 依赖；阶段 4 后为远程 exact 版本。本地调试可临时 `swift package edit` 或 Xcode 本地覆盖，**不得提交**。 |
| 发布 | 不触发 TestFlight；macOS 发布流程不变。 |
| 回滚 | 每阶段一个 PR，revert 即回滚；阶段 4 的 adopt PR 与删除 `Packages/VoxKit` 在同一 PR，revert 原子恢复。 |

## 6. 移除或改变的行为（Removed behaviour）

每项需 Owner 在对应阶段 PR 上批准（PR 打 `owner-review`）。

| # | 移除/改变 | 阶段 | 理由 | 测试影响 |
|---|---|---|---|---|
| RB-1 | `LLMTranscriptionMerger` 的 5 处内容日志 → 只记长度与回退原因枚举 | 1 | 宪法 IV（KI-1） | 新增隐私金丝雀测试 |
| RB-2 | `LocalWhisperRawOutputLogger` 删除（不再记录原始输出） | 1 | 宪法 IV（KI-1） | **`LocalWhisperRawOutputLoggerTests` 删除**（Owner Q7 已批准），新增「日志不含转写」测试 |
| RB-3 | WhisperKit 遥测 `reason` 自由文本 → `error_kind` 枚举 | 1 | 宪法 IV（KI-2） | 遥测键断言更新 |
| RB-4 | SDK 内所有插值日志改为 `StaticString` + 字段；非允许名单的控制台日志文本改变 | 1 | R3 类型化 | 无既有断言依赖（已核查只有 RB-2 的测试） |
| RB-5 | SDK 候选错误 case 改由 `VoxKitError` 承载 | 1 | SDK 不得依赖 VoxDomain | `LLMKitTests` 中 `catch VoxError.llmProviderNotConfigured` 改为 `VoxKitError`（同语义） |
| RB-6 | 测试 fixture 中的 Azure 资源主机名换成 `example.services.ai.azure.com`；需要真实 endpoint 的配置只放 gitignore 的本地文件，仓内提交 `.example` 模板（Owner Q2） | 1 | 宪法 V（KI-3） | 断言值同步替换，覆盖不变 |
| RB-7 | SDK public API 移除 Combine publisher；App 经 `VoxKitBridge` 获得同形状 publisher | 1 | R4 | 桥接行为测试新增 |
| RB-8 | `LLMProviderConfig.options` 的 `analysis.*.provider` 字符串路由、`setSkipContentAnalysis`、`MultiRecognizerTranscriber.merger` 可变注入被 workflow 定义替代 | 3 | 流程改由 workflow 表达 | 覆盖这些 API 的测试迁为 golden/preset 测试 |
| RB-9 | App 中 `TranscriberProvider` 枚举与 `ServiceContainer.makeTranscriber` 分支 → preset id | 3 | 同上 | `TranscriberSelectionTests` 迁为 preset 选择测试，矩阵不缩小 |
| RB-10 | `Packages/VoxKit` 从 VoxPocket 删除（历史保留） | 4 | 改为远程依赖 | SDK 测试在 VoxKit repo 运行 |
| RB-11 | iOS 录音：停止时释放 `AVAudioSession`（`setActive(false)`），收到中断/路由变化通知时停止录音并发 `interrupted` 状态；改用 `AVAudioApplication` 请求权限 | 1 | iOS 支持（D3）；今天中断时行为未定义 | 新增 iOS Simulator 测试；iOS App 未发布 |
| RB-12 | 阶段 3 起同一层的意图/语气分析并发执行；golden 对同层调用按 (provider, 步骤) 排序比较 | 3 | workflow DAG 语义（需求稿「intent ∥ tone」） | golden 比较规则放宽（仅顺序） |
| RB-13 | 阶段 PR 以 merge commit 合并，`auto-merge.yml` 对 `preserve-history` 标签不挂 squash | 0b | 保留逐层 commit 与 mv 历史供 filter-repo | policy 变更 |

## 7. 非目标

- 设置页 workflow 编辑 UI（#53）；新增 SR/LLM 供应商；iOS TestFlight 发布；更改默认模型或 prompt 文案；私密基准测试 `PrivateTranscriptionBenchmarkTests` 的迁移（留在 VoxPocket，作为 VoxKit 的消费者测试）。

## 8. Owner 决策

全部已由 Owner 决定，见 [`plan.md` §12](./plan.md#12-owner-决策已定2026-09-24)。
