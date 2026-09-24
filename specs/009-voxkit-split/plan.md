# VoxKit 拆分计划（S6）

- Spec：[`spec.md`](./spec.md) · 任务：[`tasks.md`](./tasks.md) · 调研：[`research.md`](./research.md)
- 模式：`repo-kit split`（切接缝 → 搬迁 → 补齐能力 → 拆 repo → 新 repo `init` → 原 repo `adopt`）
- 前置：Owner 执行顺序中 VoxKit 步骤（S6）排在「VoxPocket 按 shared-ci 合同改造（S3）」与「零知识测试（S5）」之后；本 spec/plan 经 Owner 批准。

## 1. 总则

1. **一阶段一 PR，一层一 commit**。commit 的「层」= 一个 SPM package（`VoxKit`、`VoxInfrastructure`、`VoxApplication`、`VoxPresentation`）、App 壳 `VoxPocket/VoxPocket/**`（含 `VoxPocketTests`、`project.yml`）、`docs/**`+`.specify/**`、`scripts/**`、`.github/**`。每个 commit 都能独立 build/test（pre-commit 按层增量验证，不用 `--no-verify`）。
   - **构建规则**：每个 commit 必须能 build/test **本层及其所依赖的层**；下游层可以在同一 PR 内、直到其消费方 commit 之前暂时编译失败（例外 E3），**PR head 必须全绿**。pre-commit 只验证暂存的层，因此 E3 由 PR 的 CI 兜底；合并用 merge commit，这些中间 commit 会进入 `main`，`git bisect` 时用 `--first-parent`。
   - **已知例外**（每处在 PR 描述中列出）：(E3) 1.5–1.10（kit 初始化参数由 `Logger` 改为 `VoxLogger`，App 在 1.10 跟上）、2.1–2.7（模块改名无法 shim）、3.8–3.10（Application 在 3.9 改接口，App 壳在 3.10 跟上）；(E1) 阶段 2 的搬迁 commit 同时改 `Packages/VoxKit` 与 `Packages/VoxInfrastructure/Package.swift`，否则无法构建；(E2) 阶段 4 adopt 时所有 manifest 在同一 commit 从 path 切到 url（SwiftPM 不允许同一 package identity 既是 path 又是 url）。
2. **历史保留的合并方式**：`auto-merge.yml` 会对非 draft PR 挂 squash auto-merge；squash 会抹掉「一层一 commit」与阶段 2 的「纯 mv commit」，导致 filter-repo 后丢失跨目录历史。因此：**PR-0b** 先给 `auto-merge.yml` 增加「带 `preserve-history` 标签的 PR 不挂 auto-merge」，并监听 `labeled` 事件：打标签时执行 `gh pr merge --disable-auto`；同时更新 AGENTS.md 与 CLAUDE.md「Git Workflow」中「所有 PR squash auto-merge」的表述；阶段 PR 均打 `preserve-history` 与 `owner-review`，Owner approve 后用 **merge commit**（`gh pr merge --merge`，ruleset 已允许 `merge`）合并。`git log --follow` 证据在合并后于 `main` 上采集。这是 policy 变更，需 Owner 批准（§12 Q9）。
3. **行为不变到阶段 3 结束**：阶段 1、2 只做结构调整；阶段 3 用 workflow 替换写死的流程，由 golden 证明等价。spec §6 的 RB 项是唯一例外，每项单独 commit，并在 PR 的「Removed or weakened tests or policy」段逐条列出。
4. **Golden 先行**：阶段 1 最先的两个 commit 是「注入接缝（零行为变化）」与「golden 基线」（§3.4）。
5. **不跨层混改**；每层带着该层 `red_lines` 修。
6. 阶段 PR 以 Draft 开，required 全绿 + Owner approve 后转 ready 并 merge commit 合并。

## 2. 目标结构

### 2.1 VoxKit 模块（阶段 1 建包，阶段 2 填满；阶段 4 后在 `LeePepe/VoxKit` 根目录）

依赖图（无环）：

```
VoxCore ← VoxSpeech ← VoxSpeechWhisperKit
VoxCore ← VoxRefine ← VoxLLM
VoxWorkflow → {VoxCore, VoxSpeech, VoxRefine, VoxLLM, AsyncAlgorithms}
VoxWorkflowWhisperKit → {VoxWorkflow, VoxSpeechWhisperKit}
```

| Module | 内容 | 依赖 |
|---|---|---|
| `VoxCore` | 阶段 1：`VoxKitError`、`VoxLogger`/`VoxLogField`/`VoxLabel`、`VoxTelemetry`/`VoxTelemetryEvent`、`CredentialProvider`/`CredentialKey`、`VoxStorageLocations`、Noop 实现。阶段 2 加入共享值类型与跨模块协议：`TranscriptionResult`、`TranscriptionResultType`、`TranscriptionEvent`、`AudioCaptureState`、`TranscriptionMerger` 协议、`mergedTranscription(...)`、`ModelLoadingState` | 无 |
| `VoxSpeech` | 采集（`MicrophoneRecorder` → `MicrophoneCapture`）、Apple Speech、Azure batch（`WhisperEngine`/`AzureWhisperTranscriber`）、Azure realtime（`Realtime*`）、`HybridWhisperTranscriber`、`HybridRecordingLifecycle`、`DefaultSelectableTranscriptionCoordinator` 的 async 核心 | VoxCore |
| `VoxSpeechWhisperKit` | `WhisperKitTranscriber`、`HybridLocalWhisperTranscriber`、`LocalWhisperKitConfig`、`LoadingFallbackTranscriptionCoordinator`、engine pool | VoxSpeech, WhisperKit |
| `VoxRefine` | 纯值与纯函数：`RefinementType`、`RefinementPromptBuilder`、`RefinementRequest`/`RefinementResponse`、`TranscriptionMetadata`、`IntentAnalysis`/`IntentType`/`FastIntentAnalysis`/`ToneAnalysis`/`AnalysisModels`（含 `AnalysisStep`/`AnalysisRequest`/`PartialAnalysis`） | VoxCore |
| `VoxLLM` | `LLMProvider`/`LLMService` 协议（async 形状）、`LLMProviderConfig`、`AppleIntelligenceProvider`、`AzureFoundryProvider`、`DefaultLLMService`（阶段 3 后变 internal）、`LLMTranscriptionMerger` | VoxCore, VoxRefine, AsyncAlgorithms |
| `VoxWorkflow` | 引擎与内置节点/preset（阶段 3） | 见图 |
| `VoxWorkflowWhisperKit` | 本地 WhisperKit 的节点与 preset（阶段 3） | 见图 |

与需求稿的差异：`LLMTranscriptionMerger` 放 `VoxLLM`（它依赖 `LLMService`），`VoxRefine` 只保留无 I/O 的 refine 类型与 prompt；这样 provider 可依赖 prompt 构建而不成环。

**类型级映射，一文件一目的地**：阶段 1（1.6）先把混合文件拆开，使每个文件只含去往同一模块的类型：`TranscriptionMerger.swift` 拆出 `MultiRecognizerTranscriber.swift`（Combine 形状，进 `Combine/`，阶段 2 去 Bridge）；`AudioCaptureService.swift` 拆出 `AudioCaptureState.swift`（去 VoxCore）；`ModelLoadingObservable.swift` 拆出 `ModelLoadingStartControlling.swift`（无 Combine，去 VoxSpeechWhisperKit，`DefaultRecordingUseCase` 经 public API 使用）。1.6 同时加检查脚本 `scripts/redlines/module-map.py`：读 `module-map.json`（文件→目的模块），断言每个 kit 文件恰有一个目的地、目的模块的依赖闭包包含该文件用到的所有类型所在模块（按 import 与类型名粗检）。

文件→模块映射（阶段 2 的 mv 清单，即 `module-map.json`）：TranscriptionKit 文件（数量以 `module-map.json` 为准）中，`TranscriptionResult`、`TranscriptionMerger`（仅协议与 `mergedTranscription`）、`AudioCaptureState`、`ModelLoadingState` → VoxCore；`ModelLoadingStartControlling` 与 WhisperKit 相关 → VoxSpeechWhisperKit；`Combine/` 下全部 → 阶段 2 先随 kit 进 VoxKit 的过渡 target，2.4 再进 Bridge；`WhisperKitTranscriber`、`HybridLocalWhisperTranscriber`、`LocalWhisperKitConfig`、`LoadingFallbackTranscriptionCoordinator`、`ModelPreloadControlling` → VoxSpeechWhisperKit；其余 → VoxSpeech。LLMKit：`Models/*`、`Utilities/RefinementPromptBuilder` → VoxRefine；`Protocols/*`、`Providers/*`、`Services/*`、`LLMTranscriptionMerger` → VoxLLM。**非移动的改动**（import、access level）只在紧随的 edit commit 中，不与 mv 同 commit。

### 2.2 Combine 与 async 的归属（M2）

| 类型 | 阶段 1 | 阶段 2 起 |
|---|---|---|
| `TranscriptionCoordinator`、`AudioCaptureService`、`SpeechRecognitionService`、`MultiRecognizerTranscriber`、`ModelLoadingObservable`（Combine 形状；拆分后的文件只含这些） | 保留在 kit，但**每个实现类的 Combine conformance 移到同 target 的 `Combine/` 子目录**（`<Type>+Combine.swift`），核心类只暴露 async `SpeechSession`/`events()` | `Combine/` 目录整体 mv 到 App 侧 `VoxKitBridge`，形状与签名不变 |
| 协议文件 `TranscriptionCoordinator.swift`、`AudioCaptureService.swift`（拆出 `AudioCaptureState` 后的剩余部分）、`SpeechRecognitionService.swift`、`ModelLoadingObservable.swift`、`MultiRecognizerTranscriber.swift` | 1.6 中**整文件**移入 `Combine/` | 随 `Combine/` 进 Bridge |
| 模型加载状态 | 新增 SDK 侧 async 协议 `ModelLoadingStateProviding { var modelLoadingState; func modelLoadingStates() -> AsyncStream<ModelLoadingState> }`（VoxCore）；`LoadingFallbackTranscriptionCoordinator` 与 `WhisperKitTranscriber` 的 `as? any ModelLoadingObservable` 改为 `as? any ModelLoadingStateProviding`；Bridge 的 `ModelLoadingObservable` 适配器包装它 | SDK 不依赖 Bridge |
| `DefaultSelectableTranscriptionCoordinator`、`LoadingFallbackTranscriptionCoordinator` | 拆为 async 核心 + `Combine/` 适配；`factory` 闭包改为 `Sendable` 工厂协议 `SpeechSessionFactory` | 同上 |
| `MicrophoneRecorder.start(bufferHandler:)` | 改为返回 `AsyncStream<AVAudioPCMBuffer>`（buffer 由内部有界通道转发）或降为 `package`；VoxSpeech 内部消费 | — |
| `LLMService`、`DefaultLLMService`（`import Combine` 但无 publisher） | 删除无用 `import Combine` | 在 VoxLLM |
| `TranscriptionResult` | 仍在 TranscriptionKit（阶段 1 **不移动文件**；VoxCore 不重复定义） | mv 到 VoxCore |
| `VoxError` 的 kit 相关 case | kit 改抛 `VoxKitError`（新类型在 VoxCore） | — |

R4（无 Combine 公共 API）在阶段 1 覆盖 `Packages/VoxKit/Sources` 与两个 kit 中 `Combine/` 以外的文件；阶段 2 起覆盖整个 `Packages/VoxKit/Sources`。R1–R3 覆盖 **Sources**（阶段 1：`Packages/VoxKit/Sources` 与两个 kit 的 Sources；阶段 2 起：`Packages/VoxKit/Sources`）；R5 额外覆盖 Tests 与 Examples（今天 `WhisperEngineRequestTests` 含 `VoxPocket` 字样，在 KI-4 commit 中修正）。测试代码的 env 开关（`GuidedGenerationTests` 的 `VOX_RUN_GUIDED_GENERATION_TESTS`）与 `print` 不属于 SDK 发布面，不受 R1/R3(b) 约束，但阶段 4 前改为 `XCTSkip` + test plan 开关并移除内容打印（T108a）。**T105 先对当前代码跑一次全部规则，产出违规基线清单，每一项映射到一个任务**；GATE-1 要求清单清零。

### 2.3 App 侧

| Layer | 变化 |
|---|---|
| VoxDomain | 不变 |
| VoxInfrastructure | 阶段 1 新增 `VoxKitBridge` target：`LokiVoxLogger`、`LokiVoxTelemetry`、`EnvironmentCredentialProvider`（包装已加载的 env/私密配置快照，不自行读取）。阶段 2：删除 TranscriptionKit/LLMKit target；`VoxKitBridge` 接收 `Combine/` 适配器。阶段 3：`StageModelSettings` → preset 映射、workflow 驱动的 `TranscriptionCoordinator` 与 refine runner |
| VoxApplication | import 调整；阶段 3 `DefaultRefinementUseCase` 改用 `RefineWorkflowRunning`（唯一路径） |
| VoxPresentation | 只改 import；不新增 UI（#53） |
| App 壳 | 只组装；阶段 3 删除 `injectMergerIfNeeded` 与 transcriber 分支 |

修宪后的依赖方向：`VoxPresentation → VoxApplication → VoxInfrastructure → VoxDomain`；`VoxInfrastructure、VoxApplication、VoxPresentation → VoxKit(外部)、LokiKit(外部)`；VoxKit 不依赖任何 App layer、VoxDomain、LokiKit。

### 2.4 公共 API 形状（阶段 1 定稿 VoxCore，阶段 3 补 workflow）

```swift
public protocol CredentialProvider: Sendable {
    func credential(for key: CredentialKey) async throws -> Credential?
}
public protocol VoxLogger: Sendable {
    func log(_ level: VoxLogLevel, _ message: StaticString, _ fields: [VoxLogField])
}
public enum VoxLogField: Sendable {   // 键为 StaticString；无 String 负载
    case count(StaticString, Int), durationMs(StaticString, Int)
    case flag(StaticString, Bool), label(StaticString, VoxLabel)
}
public enum VoxLabel: Sendable {      // 封闭：内置 provider/节点/步骤/回退原因/错误种类
    case provider(BuiltinProvider), node(BuiltinNode), step(AnalysisStepLabel)
    case fallback(FallbackReason), errorKind(ErrorKind)
    case custom(index: Int)           // 宿主注册的节点/provider 只以注册序号记录，永不记录原始 id
}
public protocol VoxTelemetry: Sendable { func track(_ event: VoxTelemetryEvent) }  // 同样只有 StaticString 名与受限字段
public struct VoxStorageLocations: Sendable { public let temporaryAudio: URL; public let modelCache: URL }

public protocol SpeechSession: Sendable {
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error>   // partial / final / level / state
    func stop() async
    func cancel() async
}
```

阶段 3 的 workflow 有**两个入口**（对应 App 的两个用例）：`speech`（capture → transcribe → [merge] → final text）与 `refine`（text + customPrompt + metadata → analyze(intent ∥ tone) → refine → 流式 chunk）。一个 `Preset` = 一对 `WorkflowDefinition`（`speech`、`refine`），录音结束后由 App 把终稿（或用户编辑后的文本）作为 `refine` 的输入。

## 3. 阶段 1：仓内切接缝（PR-1）

**目标**：建 `Packages/VoxKit`（只有 VoxCore）；TranscriptionKit/LLMKit 原地从 LokiKit 改为 VoxCore 协议，内部改为 async 核心 + 隔离的 Combine 适配；App 壳实现适配器；SDK 相关代码 iOS Simulator 测试修绿后改为 required。行为不变（RB-1…RB-7、RB-11 除外）。

### 3.1 子任务（按 commit 顺序）

| # | 层 | 内容 |
|---|---|---|
| 1.0a | VoxInfrastructure | **注入接缝（零行为变化）**：`HybridWhisperTranscriber`/`HybridLocalWhisperTranscriber`/`AppleSpeechTranscriber` 新增 internal init，接收录音源、识别器、`WhisperEngine`、realtime 会话工厂；公开 init 转调并传入与今天完全相同的默认实现。审查标准：公开 init 行为逐字不变，只加参数 |
| 1.0b | VoxInfrastructure/Tests + `scripts/tests` | **Golden 基线**（§3.4），在 1.0a 的代码上录制 |
| 1.1 | docs/.specify | **修宪 1.2.0**（§8）+ 新增 `Packages/VoxKit/tech-context.md` 的 red_lines 投影 + 根 tech-context/AGENTS layer 表/dependency-graph 加 VoxKit + `scripts/gates/check_frontmatter.py` 识别 VoxKit 层（Governance：规则与 red_lines 同一变更，先于代码） |
| 1.2 | VoxKit | 新包：VoxCore（§2.4，`VoxKitError.errorDescription` 与 `VoxError` 对应 case 逐字相同）、`VoxCoreTests`、Swift 6 语言模式、iOS 26/macOS 26 |
| 1.3 | VoxKit | `scripts/redlines/`：R1–R5 检查 + 每条规则的负例 fixture + `--self-test`（§6） |
| 1.4 | VoxKit | 隐私金丝雀测试工具（`CanaryLogger`/`CanaryTelemetry`，供两个 kit 与后续 VoxWorkflow 使用） |
| 1.5 | VoxInfrastructure | 按文件分组的多个 commit：`import LokiKit` → `import VoxCore`；`Logger` → `VoxLogger`；插值日志 → `StaticString` + 字段（RB-4）；RB-1、RB-2、RB-3、RB-5、RB-6 各一个 commit；`VoxPocket/TemporaryAudio`、`VoxPocketWhisperKitHub` 改由注入的 `VoxStorageLocations` 提供（KI-4）；删 `CoreModels` 依赖；删无用 `import Combine` |
| 1.6 | VoxInfrastructure | async 核心 + `Combine/` 子目录适配（§2.2，RB-7）；新 target `VoxKitBridge`（Loki 适配器、`EnvironmentCredentialProvider`） |
| 1.7 | VoxInfrastructure | iOS 采集：`AVAudioApplication.requestRecordPermission`、停止时 `setActive(false, .notifyOthersOnDeactivation)`、中断/路由变化通知处理（RB-11）；合成音频源 |
| 1.8 | VoxApplication | import 调整（错误匹配如有） |
| 1.9 | VoxPresentation | import 调整 |
| 1.10 | App 壳 | `ServiceContainer` 构造并注入 `LokiVoxLogger`/`LokiVoxTelemetry`/`VoxStorageLocations`（值与今天路径相同）/`EnvironmentCredentialProvider`；`LLMAppConfig` 仍是唯一 env/私密配置读取点；`VoxPocketLogging.allowedMessages` 同步静态消息；`scripts/tests/test_realtime_config.py` 的临时包增加 `VoxKitBridge`/VoxKit 依赖（它把 App 壳文件编进临时包） |
| 1.11 | .github | CI 新增（非 required）：`SPM VoxKit`（macOS）、`iOS SDK`（`xcodebuild test` 于 iOS Simulator，用专用 test plan `VoxKitSDK.xctestplan` 只包含 `Packages/VoxKit` 与 VoxInfrastructure 的 TranscriptionKit/LLMKit/VoxKitBridge test targets，排除基准与 PlatformAdapters）、`SDK red lines`（`Lint & policy` 内步骤，含 `--self-test`）、`App unit tests`（`xcodebuild test -scheme VoxPocket -only-testing:VoxPocketTests -destination 'platform=macOS'`，无签名，覆盖 `TranscriberSelectionTests` 等今天 CI 未跑的测试） |
| 1.12 | scripts/rulesets | `main-protection.json` 加入 `SPM VoxKit`、`iOS SDK`、`App unit tests`。**只改文件**；PR-1 合并后由 Owner 批准执行 `scripts/rulesets/apply`（先合并再 apply，避免其他 PR 等待 main 上尚不存在的 check） |

> 若开工时 S3 已把 CI 改为 shared-ci caller，1.11 的 lane 以 `quality.yml` 的 build/test 输入接入，check 名按 S3 的映射；以当时 ruleset 为准，required 不减少。

### 3.2 验收

- Golden（§3.4）相等：US1-AC1；US1-AC2、AC5、AC6、AC7。
- R1–R5 在阶段 1 范围（§2.2）通过，负例 self-test 通过：US2-AC2、AC3、AC4（阶段 1 范围）、AC6；US4-AC1、AC2、AC4。
- `iOS SDK` lane 绿：US5-AC1（阶段 1 部分）、US5-AC2。
- US7-AC1、AC2；`check_frontmatter.py` 通过。

### 3.3 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| async 核心 + Combine 适配改变事件时序（partial/final 顺序、终稿只发一次） | UI 自动停止、快捷录音 15s 等待 | 适配器用单一有序流转发；golden (c) 记录事件顺序；`EditorAutoStopRaceTests`、`QuickRecordingViewModelTests` 不改 |
| ~114 处日志改造，commit 过大 | 审查困难 | 1.5 按文件分组拆 commit；每个 commit 通过层测试 |
| iOS Simulator 上 SFSpeech/AVAudioEngine/FoundationModels 不可用 | iOS lane 红 | 测试只用注入的假实现与合成音频；真实适配器只要求编译；FoundationModels 用可用性判定 |
| iOS lane 修不绿 | 不能改 required | 以 issue 跟踪，保持非 required，并阻塞阶段 4（US6-AC3 要求 iOS required） |
| `test_realtime_config.py` 临时包漏依赖 | CI 红 | 1.10 同 commit 更新 |
| RB-11 改变 iOS 录音中断行为 | iOS App（未发布）行为变化 | Owner 批准；iOS 不发布（D3） |

### 3.4 Golden 设计

分三组，全部用**版本化 trace schema**（`golden-trace/v1`），记录在边界协议上（LLM provider、识别器、合并器、日志与遥测 sink），而不是在具体类上；每个阶段只换薄的「探针适配器」（阶段 1 前适配 LokiKit `Logger` 与 Combine，阶段 1 后适配 `VoxLogger` 与 async），schema 与 fixture 不变。

| 组 | 接缝 | 位置 | 内容 |
|---|---|---|---|
| (a) LLM/分析/精炼 | 现有 `@testable DefaultLLMService.init(providers:logger:)` | `VoxInfrastructure/Tests/GoldenTraceTests/LLM*` | 每次 provider 调用（provider、方法、prompt 原文、步骤集合）、`RefinementResponse` 字段、`missingAnalysisSteps`、流式 chunk 序列。矩阵：分析 {skip, 全 Apple, 全 Azure, intent Apple/tone Azure, intent Azure/tone Apple} × {成功, 单步失败, provider 缺失} × {refine, refineStreaming}；合并器 {成功, 抛错, 超长, 两路相同, Apple 为空} |
| (b) 纯逻辑（macOS 行由 harness 产出；`#if os(iOS)` 分支的行由 `iOS SDK` lane 中的同名测试产出） | `HybridRecordingLifecycle`、`RealtimeASRFinalizer`、`mergedTranscription`、`StageModelRouting.resolveTranscriber`/`resolvedSpeechModel`/`analysisOptions`、`DefaultStageTextModelService` 的配置失败语义 | TranscriptionKit 测试 + `scripts/tests/test_golden_routing.py`（仿 `test_realtime_config.py`，把 App 壳文件编进临时包） | EB-1 表全部行 × iOS/macOS 分支；EB-7 Azure 未配置 |
| (c) 端到端转写 | 1.0a 的注入接缝 | `VoxInfrastructure/Tests/GoldenTraceTests/Speech*` | Hybrid × {realtime 成功, realtime 失败→batch, 静默跳过, 有/无合并器}；事件序列（类型、文本、顺序）；主/快捷两栈并行各一次 |

所有组都记录：遥测事件名与属性键、Loki 允许名单内的日志消息。

**`pipeline` 描述（跨阶段可比的中性表示）**：`golden-trace/v1` 含 `pipeline` 字段——`speech: [节点 kind…]`（如 `[capture.microphone, speech.apple, speech.azure.realtime, speech.azure.batch]`）、`realtime: bool`、`merger: bool`、`analysis: {intent: provider|skipped, tone: provider|skipped}`、`refine: provider`、`configFailure: none|textModelUnavailable`。基线时由 (b) 的探针从 `resolveTranscriber`/`resolvedSpeechModel`/`DefaultStageTextModelService` 的结果导出；阶段 3 起由 `Preset.default.overriding(StageModelSettings 映射)` 的定义导出；两者对 `StageModelSettings` 全组合 × {配置齐全, batch 缺失, realtime 缺失, Azure 文本缺失} 逐项相等。(c) 阶段 3 起：`Hybrid*Transcriber` 的核心逻辑成为 `speech.*`/`merge.llm` 节点的实现，1.0a 注入的同一组假识别器/录音源/`WhisperEngine`/realtime 工厂在节点边界注入，事件序列与基线比较。

**比较规则**：
- 同一 provider 内 intent 组先于 tone 组（今天由代码保证）→ 严格比较。
- **跨 provider 的分析组顺序今天就不确定**（`stepsByProvider` 是 `Dictionary`，每进程哈希种子不同）→ 从基线起就按 (provider, 步骤) 排序比较。
- 阶段 3 起同一层分析并发：同层调用按 (provider, 步骤) 排序比较（RB-12），其余字段逐项相等。
- RB-3 的 `reason` → `error_kind` 在其 commit 内同时更新基线（单独的 baseline-update 提交，列在 PR）。

**不覆盖**（如实声明）：真实麦克风、SFSpeechRecognizer 识别结果、AVAudioEngine 时序、真实网络、FoundationModels 输出。它们由既有集成测试与人工 TestFlight 使用覆盖。

**Fixture 位置**：阶段 1 在 `VoxInfrastructure/Tests/GoldenTraceTests/Fixtures`；阶段 2 起 (a)(c) 在 `Packages/VoxKit/Tests/GoldenTraceTests/Fixtures`，(b) 在 `scripts/tests/golden/`；两处共用的 `pipeline` 描述 fixture **复制**一份，`scripts/tests/check_golden_drift.py` 比较 schema 版本与内容哈希；阶段 4 后 drift 检查改为比较 App 侧副本与所 pin 版本 VoxKit tag 中的副本（T409）。

### 3.5 PR 边界

PR-1 = 1.0a–1.12。**不移动文件**。合并条件：required 全绿，Owner approve（修宪、RB-1…RB-7、RB-11、ruleset 文件）后 merge commit 合并；合并后 apply ruleset 并回读。

## 4. 阶段 2：搬迁（PR-2）

**目标**：按 §2.1 映射把 TranscriptionKit/LLMKit 源与测试 `git mv` 进 `Packages/VoxKit`；`Combine/` 适配 mv 进 `VoxKitBridge`；App 改为依赖 VoxKit。只移动与 import 调整，行为不变。

### 4.1 子任务

| # | 层 | 内容 |
|---|---|---|
| 2.1 | VoxKit + VoxInfrastructure/Package.swift（E1） | 按模块分组的 mv commit：每个 commit 只 `git mv` 一个模块的文件，并做**最小** manifest 修改使其可构建（VoxKit 内暂用原 target 名 `TranscriptionKit`/`LLMKit` 作为过渡，VoxInfrastructure 改为依赖 `../VoxKit` 的这些 product）。不改任何 `.swift` 内容，保证 rename 检测 100% |
| 2.2 | VoxKit | edit commit：拆分为 §2.1 的模块名、import、access level（优先 `package`）、测试 target 对应拆分（`@testable` 18 处随被测类型走）；golden (a)(c) 与 fixture 随之 mv 到 `Packages/VoxKit/Tests/GoldenTraceTests`（`package`/`@testable` 不跨包可见），(b) 与 Bridge 映射留在 VoxPocket |
| 2.3 | VoxKit | `Examples/MinimalConsumer`（macOS + iOS）；「只依赖 VoxSpeech 的产物中无 WhisperKit 模块/符号」检查 |
| 2.4 | VoxInfrastructure | `Combine/` 适配从 VoxKit 过渡 target 再 mv 进 `VoxKitBridge`（mv commit + edit commit）；删除 WhisperKit、async-algorithms 依赖（旧 `TranscriptionKit`/`LLMKit` target 已在 2.1 删除以避免模块名冲突）；`PrivateTranscriptionBenchmarkTests` 改依赖 VoxKit products |
| 2.5 | VoxApplication | 依赖改为 VoxKit / `VoxKitBridge` |
| 2.6 | VoxPresentation | 同上 |
| 2.7 | App 壳 | import、`project.yml`、`scripts/tests/*.py` 临时包依赖 |
| 2.8 | .github | red lines 扫描范围 = `Packages/VoxKit/Sources` 全部；R4 全量；fixture 构建步骤（macOS + iOS Simulator） |
| 2.9 | docs | tech-context/frontmatter/AGENTS：VoxInfrastructure 职责去掉「转写 / LLM」，`owns` 去掉 TranscriptionKit/LLMKit、加 VoxKitBridge |

### 4.2 验收

- US1-AC1…AC7（golden 全组相等）；US2-AC1（fixture 以 path 依赖在 macOS 与 iOS Simulator 构建）；US2-AC4（R4 全量）、US2-AC5。
- 合并（merge commit）后在 `main` 上抽查 3 个跨模块迁移文件的 `git log --follow`，能看到阶段 1 之前的提交；结果贴在 PR 评论（US6-AC1 前置）。

### 4.3 风险

| 风险 | 缓解 |
|---|---|
| 跨模块暴露 internal 类型 | 先 mv 后改 access；只把真正跨模块使用的设为 `package`/`public` |
| WhisperKit 仅 product 隔离，仍被解析 | 按 research R-3 如实写入 `ai/COMPATIBILITY.md`；是否拆第二个包由 Owner 定（§12 Q3） |
| 合并方式不是 merge commit 导致历史丢失 | PR-0b + `preserve-history` 标签；合并前 checklist |

### 4.4 PR 边界

PR-2 = 2.1–2.9。不改任何流程逻辑。

## 5. 阶段 3：Workflow 引擎（PR-3，两组 commit）

默认**一个 PR**：先是 SDK 组（只动 `Packages/VoxKit`），再是 App 组。若 Owner 同意，可拆成 PR-3a/PR-3b（§12 Q5）。

### 5.1 SDK 组（只增，不改 App）

| # | 内容 |
|---|---|
| 3.1 | `Definition`：`WorkflowDefinition{version, entry: .speech/.refine, nodes: [NodeSpec]}`、`NodeSpec{id, kind: NodeKindID, inputs: [PortRef], params: JSONValue, onFailure: FailurePolicy}`；Codable；执行前校验（未知 kind、悬空引用、环、端口类型、入口不匹配） |
| 3.2 | `Registry`：`NodeKindID`（`capture.microphone`、`speech.apple`、`speech.azure.batch`、`speech.azure.realtime`、`speech.whisperkit.local`、`merge.llm`、`analyze.intent`、`analyze.tone`、`refine.prompt`、`llm.apple`、`llm.azure`、`output.text`）→ 工厂；宿主可注册自定义节点（日志中记为 `VoxLabel.custom(index:)`） |
| 3.3 | `Scheduler`：拓扑分层；同层 `withThrowingTaskGroup` 并发（节点可声明 `concurrency: 1`）；流式端口用 `AsyncThrowingChannel`，多路 partial 用 `merge`；失败策略 `fail`/`fallback(nodeID)`/`default(JSONValue)`；取消传播 |
| 3.4 | `Events`：`WorkflowEvent`（`partial`、`final`、`level`、`nodeStarted/Finished/Failed(label, reason: VoxLabel)`、`refinedChunk`、`completed`） |
| 3.5 | `DSL`：`@WorkflowBuilder`；`Preset{id, speech, refine}`；`overriding(_:)`，override 键：`speech`、`analysis.intent`、`analysis.tone`、`analysis.skip`、`refine.provider` |
| 3.6 | 内置 preset：`hybrid.azure`、`apple.speech`、`hybrid.local` 与 `local.whisperkit`（后两者在 `VoxWorkflowWhisperKit`） |
| 3.7 | 测试：US3-AC1…AC7；SDK 侧 golden (a)(c) 用复制的 fixture；隐私金丝雀跑全部 preset |

### 5.2 App 组（一层一 commit）

| # | 层 | 内容 |
|---|---|---|
| 3.8 | VoxInfrastructure/VoxKitBridge | `StageModelSettings` → `Preset.default.overriding(...)` 映射（EB-1、EB-7、EB-8、EB-9），全组合测试；iOS 路径：偏好 `llm.provider`/`llm.skipContentAnalysis` → `overriding(refine.provider, analysis.skip)`，并在 `llmProviderDidChange`/`llmAnalysisSettingsDidChange` 通知时重新应用；`WorkflowTranscriptionCoordinator` 转发 `ModelLoadingStartControlling`（保持本地 Whisper「模型未就绪阻止开始录音」，加测试）；`WorkflowTranscriptionCoordinator`（以 `speech` 入口实现 `TranscriptionCoordinator`）；`RefineWorkflowRunner`（`refine` 入口） |
| 3.9 | VoxApplication | `DefaultRefinementUseCase` 改为只依赖 `RefineWorkflowRunning`（**唯一路径**；不保留 `LLMService` 分支） |
| 3.10 | App 壳（含 `VoxPocketTests`） | 同一 commit：删除 `injectMergerIfNeeded`、transcriber `switch`、`TranscriberProvider`、`DefaultStageTextModelService`、`StageModelRouting.applyTextModels`/`analysisOptions`/`resolveTranscriber`（RB-8、RB-9），每栈独立 `WorkflowRuntime`；iOS `ServiceContainer`（`#else` 分支的 `DefaultLLMService`、`setProvider`、`setSkipContentAnalysis`、偏好通知观察）改接 3.8 的 iOS 映射；`TranscriberSelectionTests`/`RealtimeTranscriberConfigurationTests` 迁为 preset 选择测试（矩阵不缩小）；`scripts/tests/test_realtime_config.py` 同步 |
| 3.11a | VoxInfrastructure | `PrivateTranscriptionBenchmarkTests` 改用 public 的 refine workflow / preset API（今天直接构造 `DefaultLLMService` 并实现 `LLMService`）；该 target 默认跳过，但必须编译 |
| 3.11 | VoxKit | `DefaultLLMService`、`LLMService` 降为 `package`/internal（只供节点使用），R4 与 API 快照更新 |
| 3.12 | docs | tech-context 流程描述；CLAUDE.md「Transcriber Providers」→ preset 表 |

### 5.3 验收

US1 全部（golden 按 §3.4 比较规则，RB-12 放宽；`pipeline` 矩阵含 EB-7 iOS 行）、US3 全部、US4-AC2（全部 preset）；App target 的 macOS 与 iOS build 均通过。

### 5.4 风险

| 风险 | 缓解 |
|---|---|
| 分析并发后 FoundationModels 并发会话冲突 | `AppleIntelligenceProvider` 已在内部 `async let` 并发 intent/tone；有问题时 preset 设 `concurrency: 1` |
| 分析结果今天不影响输出（research R-2） | golden 仍记录调用；§12 Q4 请 Owner 决定去留 |
| 引擎超出 600 行预算 | 只计 Definition/Registry/Scheduler/Events/DSL；超出在 PR 说明并拆文件，不引第三方引擎 |
| 主/快捷栈共享 runtime 造成污染 | 每栈独立 runtime；US1-AC4 测试 |

### 5.5 PR 边界

PR-3 = 3.1–3.12；SDK 组全部 commit 在 App 组之前。

## 6. SDK 红线的机械检查

脚本 `Packages/VoxKit/scripts/redlines/check.sh`；每条规则有 `fixtures/violations/<rule>/*.swift` 负例和 `fixtures/ok/` 正例，`check.sh --self-test` 证明负例失败、正例通过。阶段 1–3 在 VoxPocket `Lint & policy` 执行，阶段 4 后在 VoxKit 的 `quality` lint lane 执行。扫描范围见 §2.2。

| # | 红线 | 检查 |
|---|---|---|
| R1 | 不读 env、不读文件/配置 | 禁止（源码正则）：`ProcessInfo`、`getenv`、`setenv`、`environment\[`、`UserDefaults`、`@AppStorage`、`CFPreferences`、`NSUbiquitousKeyValueStore`、`Bundle\.main`、`Bundle\(for:`、`infoDictionary`、`SecItem`、`Data\(contentsOf:`、`String\(contentsOf`、`contentsOfFile`、`NSDictionary\(contentsOf`、`FileHandle\(forReading`、`InputStream\(`、任意接收者上的 `\.urls?\(for:`、`contents\(atPath:`、`contentsOfDirectory`、`applicationSupportDirectory`、`cachesDirectory`、`documentDirectory`、`homeDirectory`、`NSHomeDirectory`、`NSTemporaryDirectory`、`temporaryDirectory`、`CommandLine`、`environ\b`、`URL\(fileURLWithPath:`。**白名单**：只在新建的 `TemporaryAudioStore.swift`（1.5 的 KI-4 commit 创建；统一负责宿主注入的 `VoxStorageLocations.temporaryAudio` 下 WAV 的建目录/写/读/删，吸收今天分散在 `MicrophoneRecorder` 的 `createDirectory`/`AVAudioFile`、`WhisperEngine.swift` 的 `Data(contentsOf:)`、`AzureWhisperTranscriber`/`HybridWhisperTranscriber`/`HybridLocalWhisperTranscriber` 的 `removeItem`）与 WhisperKit 模型缓存适配器中允许（后者只允许对注入的 `VoxStorageLocations.modelCache` 下路径做 I/O；今天 `WhisperKitTranscriber` 里的 `cachesDirectory`/`homeDirectoryForCurrentUser` 路径解析在 1.5 的 KI-4 commit 中删除），且每行需 `// redline-allow: R1 <理由>`；白名单文件与允许注释数量写死在脚本里，变更属于 CODEOWNERS 覆盖的重要 PR。每个禁止 API 至少一个负例 |
| R2 | 不依赖 LokiKit / shared-telemetry | (a) 源码禁止 `import (LokiKit|SharedTelemetry|\w*Telemetry\w*)`；(b) `swift package show-dependencies --format json` 的闭包只允许白名单（`swift-async-algorithms`、`WhisperKit` 及阶段 1 固化的传递依赖快照）；(c) `Package.swift` 禁止 `path:` 指向包外 |
| R3 | 日志/遥测无转写、音频、精炼文本 | (a) 类型化：`VoxLogger.log` 只收 `StaticString` 消息与 `VoxLogField`（键为 `StaticString`，值只有 Int/时长/Bool/`VoxLabel`），`VoxTelemetryEvent` 同理——传入 `String` 无法编译（负例 fixture 以「必须编译失败」验证）；(b) 静态：禁止 `print(`、`debugPrint(`、`dump(`、`NSLog`、`os_log`、`import OSLog`、`Logger\(subsystem`；(c) 动态：隐私金丝雀测试，所有入口/preset 用含金丝雀串的假数据运行，日志、遥测、`VoxKitError.errorDescription` 与 `localizedDescription` 中不得出现金丝雀串 |
| R4 | async/await + `AsyncThrowingStream` 公共 API | (a) 源码禁止 `import Combine`；(b) 构建时 `-emit-symbol-graph`，脚本解析 public/open 符号：拒绝类型名含 `Publisher`/`Subject`/`Cancellable`；拒绝**任何** public/open 符号（参数、属性、下标、返回值）的声明片段中出现函数类型——不论是否 `@escaping`、是否 Optional（Optional 闭包隐式逃逸）；允许清单写死在脚本里（`NodeRegistry.register(_:factory:)`、`@WorkflowBuilder` 相关、`AsyncThrowingStream` 构造相关）；负例覆盖 `completion:`、`onResult:`、`callback:`、Optional completion 参数（`((Result) -> Void)? = nil`）、public 闭包属性（`var onEvent: ((X) -> Void)?`） |
| R5 | 无产品/供应商标识 | 对 `Sources/`、`Tests/`、`Examples/`：禁止 `VoxPocket`、`com\.leepepe`、`[a-z0-9-]+\.services\.ai\.azure\.com` 与 `[a-z0-9-]+\.openai\.azure\.com` 中非 `example` 的主机、GUID 形式的租户/订阅 ID |

并发（宪法 III 修订后）：`@unchecked Sendable`/`nonisolated(unsafe)` 每处须有 `// Sendable:` 理由注释，且理由属于修订后允许的类别（Combine 桥接〔仅 App 侧 `VoxKitBridge`〕、AVFoundation/Speech/WhisperKit 回调桥接）；SDK 内计数只能下降，基线在 1.2 记录（US4-AC4）。

## 7. iOS 启用路径

| 步 | 何时 | 内容 | 验收 |
|---|---|---|---|
| I-1 | S3（若未完成则在 PR-1 的 1.1 一并做） | AGENTS / constitution / CLAUDE 删除「暂停 iOS」表述；保留「iOS TestFlight 需另行授权」 | US5-AC3 |
| I-2 | PR-1 1.7 | iOS 采集完善（RB-11） | US5-AC2 |
| I-3 | PR-1 1.11 | `iOS SDK` lane：iOS Simulator 上 `xcodebuild test`，覆盖 `Packages/VoxKit` 与 VoxInfrastructure 的 kit/Bridge test targets（非 required） | — |
| I-4 | PR-1 合并后 | lane 绿 → Owner 批准 → ruleset apply（1.12） | US5-AC1 |
| I-5 | PR-2/3 | 每个 PR 跑 `iOS SDK`；App `App target` 的 iOS build 保持 | — |
| I-6 | 阶段 4 | VoxKit repo CI 的 iOS Simulator lane 属于 `quality` 的 build/test 输入（计入 `aggregate`），外部消费者 fixture 在 iOS Simulator 构建 | US6-AC3, US2-AC1 |
| — | 不做 | App iOS realtime 默认启用（`LLMAppConfig.realtimeTranscriptionConfig` 的 `#if os(macOS)` 保持）、iOS 设置页、iOS TestFlight | 另行授权 |

## 8. 宪法与 tech-context 修订（Governance 流程）

在 PR-1 的 1.1 commit 内完成，先于任何 VoxKit 代码（规则、理由、迁移影响、版本号，同步受影响 layer 的 `red_lines`）。

| 条款 | 修订 | 理由 | 迁移影响 |
|---|---|---|---|
| II 依赖方向 | 图改为 §2.3；VoxKit 不得依赖任何 App layer、VoxDomain、LokiKit | 语音能力外置 | `depends_on`、dependency-graph、packages-architecture 更新 |
| III 并发 | `@unchecked Sendable`/`nonisolated(unsafe)` 允许类别由「仅 Combine 桥接」扩为「Combine 桥接（只在 App 侧）与系统框架回调桥接（AVFoundation/Speech/WhisperKit）」，每处须注明理由；SDK 内计数只减不增 | Combine 移出 SDK 后，现有 35 处中的系统回调桥接需要合法类别 | R 检查计数 |
| IV 隐私 | 增补：VoxKit 自身受本条约束，以类型化日志 API 与 R3 强制；App 不得把 SDK 事件中的文本写入日志/遥测 | SDK 独立发布 | R3 |
| V 凭据 | 增补：只有 App 壳读取 env 与 `config.private.json`；VoxKit 不读取任何 env/文件/偏好，凭据经 `CredentialProvider` 注入 | 边界清晰 | R1；`LLMAppConfig` 为唯一读取点 |
| Additional Constraints | 「LokiKit is external」旁增「VoxKit：阶段 1–3 为本仓暂存包 `Packages/VoxKit`，阶段 4 起为远程 exact 版本依赖」；删去 iOS 暂停（若 S3 未做） | — | 阶段 4 再改一次 |
| Quality Gates | 增：SDK red lines（R1–R5）与 VoxKit iOS Simulator 测试属于 CI required | — | ruleset 经 Owner 批准 |
| 版本 | 1.1.1 → 1.2.0（增补，非破坏） | — | — |

tech-context：新增 `Packages/VoxKit/tech-context.md`（layer `VoxKit`，`depends_on: []`，roles：Types=`VoxCore`、`VoxRefine`；Repo=`VoxSpeech`、`VoxSpeechWhisperKit`、`VoxLLM`；Runtime=`VoxWorkflow`；red_lines = R1–R5 + III；test = `swift test --package-path Packages/VoxKit`）；VoxInfrastructure frontmatter 更新（阶段 1 `depends_on: [VoxDomain, VoxKit]`，阶段 2 `owns` 去掉两个 kit、加 VoxKitBridge）；Application/Presentation 的 `depends_on` 按实际 import 更新；`check_frontmatter.py` 识别 VoxKit 为本地 layer（阶段 1–3），阶段 4 改为与 LokiKit 相同的外部处理。

## 9. 拆 repo（阶段 4：VK-1 + PR-4）

前置：PR-1、PR-2、PR-3 均以 merge commit 合并到 `main`；`iOS SDK` 已 required。

1. **导出**（在临时目录的新 clone，不在任何工作 checkout 上）：
   ```sh
   git clone --no-local --no-tags <VoxPocket-url> voxkit-export && cd voxkit-export
   git filter-repo \
     --path Packages/VoxKit/ \
     --path Packages/VoxInfrastructure/Sources/TranscriptionKit/ \
     --path Packages/VoxInfrastructure/Sources/LLMKit/ \
     --path Packages/VoxInfrastructure/Tests/TranscriptionKitTests/ \
     --path Packages/VoxInfrastructure/Tests/LLMKitTests/ \
     --path LICENSE \
     --path-rename Packages/VoxKit/: \
     --path-rename Packages/VoxInfrastructure/Sources/TranscriptionKit/:Sources/VoxSpeech/ \
     --path-rename Packages/VoxInfrastructure/Sources/LLMKit/:Sources/VoxLLM/ \
     --path-rename Packages/VoxInfrastructure/Tests/TranscriptionKitTests/:Tests/VoxSpeechTests/ \
     --path-rename Packages/VoxInfrastructure/Tests/LLMKitTests/:Tests/VoxLLMTests/ \
     --replace-message message-rewrites.txt      # (#NN) → LeePepe/VoxPocket#NN，以及 Q2 选定的处置
   ```
   - 旧路径 rename 只让迁移前历史落在合理位置；`Combine/` 适配在阶段 2 已迁到 App 侧，不在导出范围内（其早期历史在 kit 路径下会被带出，属预期）。
   - 树一致性：`git fetch <VoxPocket-url> main:orig-main` 后 `git diff --stat HEAD^{tree} orig-main:Packages/VoxKit -- . ':!LICENSE'` 必须为空。
   - `--no-tags` 且推送前 `git tag -l` 为空（不带 `testflight/*` 等 tag）。
2. **隐私预检**（发现即停，交 Owner）：
   - `gitleaks detect --log-opts="--all"` 全历史；
   - 全历史 blob 与提交信息 grep：shared-ci `forbidden_patterns`（身份/本机路径）、`config.private.json` 与 `*.private.*`、`.services.ai.azure.com`/`.openai.azure.com` 非 `example` 主机、GUID、`MY-[0-9]+` 等内部 issue 号、`com.leepepe`；
   - 列出历史中所有二进制与音频 blob（`*.wav`、`*.m4a`、`*.caf`、`*.mp3`），应为零；
   - `git log --format='%an <%ae>%n%cn <%ce>' | sort -u` 列出作者/提交者；
   - 输出只含计数与 commit SHA 的报告（不贴内容）交 Owner。
   - 已知会命中：Owner 个人邮箱（作者信息）、一个提交信息中的内部 issue 号、测试历史中的 Azure 资源主机名。处置由 Owner 选（§12 Q2），选定后重跑直到零发现或每项有书面处置。
3. **建 repo 并推送**：Owner 确认后建 `LeePepe/VoxKit`（public，MIT），推 `main`。
4. **`repo-kit init`（VK-1 PR）**：按 shared-ci@<当时发布的 40 位 SHA> 模板：AGENTS.md（≤150 行；Read first / Protocol / Verify / Required checks / Red lines / Delivery / Dependencies）、thin CLAUDE.md、`scripts/verify`（macOS `swift build/test`、iOS Simulator `xcodebuild test`、`scripts/redlines/check.sh` + self-test）、`.githooks/pre-push`、caller `ci.yml`（`runs-on: macos-26`；build/test 输入含 iOS Simulator，计入 `quality / aggregate`；contract audit；workflow-lint；PR body 检查）、`review.yml` caller、PR 模板、CODEOWNERS（`/.github/`、`/AGENTS.md`、`/Package.swift`、`/scripts/redlines/`、`/ai/`）、根 `tech-context.md` layer 表（每个 module 一个 layer）；`ai/` 七件套（README/USAGE/INTEGRATION/EXAMPLES/COMPATIBILITY/MIGRATION/registry.json）。验收：shared-ci `audit` 零发现。
5. **ruleset**：old→new 给 Owner，批准后设置：禁直推；required `quality / aggregate` 与 `codex-review-target / codex-review`；回读 `rules/branches/main`。
6. **Tag**：`0.1.0`（§12 Q6），release notes 指向 `ai/`；按 W5 用 `ai/INTEGRATION.md` 的外部消费者 fixture 在干净目录以 `exact: "0.1.0"` 在 macOS 与 iOS Simulator 构建。
7. **VoxPocket `repo-kit adopt`（PR-4）**：
   - 4.1（E2）：VoxInfrastructure/Application/Presentation 的 `Package.swift` 与 `project.yml` 同一 commit 改为 `.package(url: "https://github.com/LeePepe/VoxKit", exact: "0.1.0")`，删除 `Packages/VoxKit`。
   - 4.2：`.gitignore` 只放行 `Packages/VoxInfrastructure/Package.resolved`、`Packages/VoxApplication/Package.resolved`、`Packages/VoxPresentation/Package.resolved` 与 `VoxPocket/VoxPocket.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`，并提交这 4 个文件（合同第 7 项比对依据）。
   - 4.3：CI 删除 `SPM VoxKit`、`iOS SDK` 中的 VoxKit 部分（改由 VoxKit repo required 保证），`Lint & policy` 删 SDK red lines 步骤；ruleset 映射 old→new 经 Owner 批准，合并后 apply。
   - 4.4：`check_frontmatter.py` 视 VoxKit 为外部；宪法 Additional Constraints、tech-context、AGENTS「Dependencies」段（`VoxKit 0.1.0` + `…/0.1.0/ai/` 链接）；本地切 path 依赖的方法（`swift package edit` / Xcode 本地覆盖）写入 AGENTS，**不得提交**。
   - App 侧 golden (b) 与 Bridge 映射测试、全部既有测试通过。
8. **回滚演练**：从 PR-4 开 revert 草稿分支跑 CI，绿后关闭（US6-AC6）。

## 10. PR / 阶段总览

| PR | 阶段 | 仓 | 依赖 | Owner 批准点 |
|---|---|---|---|---|
| PR-0（本 PR） | spec/plan | VoxPocket | — | spec、plan、§12 问题 |
| PR-0b | policy | VoxPocket | PR-0 | `auto-merge.yml` 的 `preserve-history` 例外（Q9） |
| PR-1 | 1 接缝 | VoxPocket | PR-0b、S3/S5 | 修宪 1.2.0、RB-1…RB-7、RB-11、ruleset |
| PR-2 | 2 搬迁 | VoxPocket | PR-1 + ruleset apply | 依赖变更、E1 |
| PR-3 | 3 引擎 + 替换 | VoxPocket | PR-2 | RB-8、RB-9、RB-12 |
| VK-1 | 4 init | VoxKit | PR-3 + 隐私预检 | 预检处置、ruleset、tag |
| PR-4 | 4 adopt | VoxPocket | VK-1 tag | 依赖 pin、E2、ruleset 映射 |

## 11. Plan-Review Loop 记录

| 轮 | 结论 | 发现 | 处理 |
|---|---|---|---|
| 1 | NEEDS_REVISION | 4 CRITICAL、12 MEDIUM、10 LOW | 见下 |
| 2 | NEEDS_REVISION | 0 CRITICAL、6 MEDIUM（C2 在文件映射层面回归 + 5 个新问题）、8 LOW；确认 C1、C3、C4、M1–M12 已解决 | 见下 |
| 3（上限） | NEEDS_REVISION | 0 CRITICAL、3 MEDIUM（N1–N3）、3 LOW；确认 M-B、M-C、M-D 已解决，M-A/M-E/M-F 规则正确但与现有代码存在未映射的违规 | 已按下列修订；**因达到 3 轮上限，修订后未再经 reviewer 复核**，交 Owner 审阅时一并确认 |

第 1 轮要点与修订：
- C1 squash 合并抹掉一层一 commit 与 mv 历史 → §1.2 `preserve-history` + merge commit，PR-0b，Q9；`--follow` 证据在合并后的 `main` 上采集。
- C2 VoxLLM↔VoxRefine、VoxSpeech→VoxRefine 成环 → §2.1 重排模块图（共享值类型/协议入 VoxCore，prompt 与 refine 类型入 VoxRefine，provider 与 merger 入 VoxLLM）并给出文件映射。
- C3 golden 无法在未改代码上驱动、够不到 App 路由 → §3.4 分三组（LLM 接缝 / 纯逻辑 + 脚本 harness / 注入接缝后的端到端），先做零行为变化的 1.0a，版本化 trace schema 加每阶段探针适配器，声明不覆盖范围。
- C4 跨 provider 分析顺序今天就是随机的 → 比较规则从基线起就归一；spec EB-8 改写。
- M1 纯 mv commit 无法构建 → E1 例外，过渡 target 名。M2 Combine 清单 → §2.2 表，阶段 1 不移动 `TranscriptionResult`。M3 iOS 中断处理 → RB-11。M4 iOS lane 覆盖 kit → `iOS SDK` lane 覆盖 VoxInfrastructure kit targets。M5 R1 补 API 与白名单。M6 `StaticString` 键、`custom(index:)`、R4 拒绝所有 public escaping 闭包。M7 修宪 III。M8 修宪先于 VoxKit 代码，新增 `check_frontmatter.py` 任务。M9 默认单 PR-3，RB-12。M10 `speech`/`refine` 双入口，refine 唯一路径。M11 manifest 同 commit 切换，放行并列出 4 个 `Package.resolved`。M12 新增 `App unit tests` lane，`test_realtime_config.py` 在 1.10/3.10 更新。
- LOW：计数修正（research）、偏好键名（spec §5）、I-2 表述、check 名 `codex-review-target / codex-review` 与 `macos-26`、filter-repo `--no-tags`/`(#NN)` 改写/树比较命令/音频扫描、ruleset 合并后 apply、fixture 复制 + drift 检查、US1-AC4/US3-AC5 措辞、外部文档引用限定、T313/T314 合并、golden 作为 PR gate 而非 commit。

第 2 轮要点与修订：
- M-A 混合文件导致 VoxCore→VoxSpeech 环、VoxCore 含 Combine → §2.1 改为类型级映射；1.6 先拆 `MultiRecognizerTranscriber`、`AudioCaptureState`、`ModelLoadingStartControlling` 为独立文件；新增 `module-map.json` + 检查脚本。
- M-B 下游层中间 commit 编译失败 → §1.1 构建规则与例外 E3，PR head 全绿，`bisect --first-parent`。
- M-C T311 使基准测试 target 编译失败、`applyTextModels` 未列入删除 → 新增 3.11a；3.10 删除列表补全。
- M-D 阶段 3 golden (b)(c) 比较无定义 → `pipeline` 中性描述字段，基线与 preset 两端导出；(c) 在节点边界注入同一组假实现。
- M-E R4 漏掉 Optional 闭包与 public 闭包属性 → 拒绝所有 public 声明中的函数类型，补负例。
- M-F R1 漏掉非 `.default` 接收者与若干 API → 放宽接收者，补 `contents(atPath:`、`NSTemporaryDirectory`、`temporaryDirectory`、`documentDirectory`、`CommandLine`、`environ`。
- LOW：`labeled` 事件与 AGENTS/CLAUDE 表述、2.1/2.4 过渡 target 说明、R1 缓存白名单收窄、R5 阶段 1 覆盖 Tests、GATE-1 要求三个新 lane 全绿、drift 检查阶段 4 重定向、golden (a)(c) 阶段 2 迁入 VoxKit、iOS lane 专用 test plan。

第 3 轮要点与修订（未复审）：
- N1 SDK 仍依赖 App 侧 Combine 协议 `ModelLoadingObservable`、协议文件无去处 → §2.2 明确四个协议文件整体进 `Combine/`；新增 SDK 侧 `ModelLoadingStateProviding`；`factory` 闭包改为 `SpeechSessionFactory` 协议；`MicrophoneRecorder.start(bufferHandler:)` 改为 `AsyncStream`。
- N2 阶段 3 漏掉 iOS 文本模型路径 → 3.8 增加 iOS 偏好映射与通知重应用，3.10 改接 iOS `ServiceContainer`，golden `pipeline` 矩阵含 EB-7 iOS 行，GATE-3 要求 iOS App build。
- N3 规则对现有代码直接失败且无任务消除 → R1/R3 限定 Sources，R5 覆盖 Tests；新建 `TemporaryAudioStore` 统一临时音频 I/O；T105 产出违规基线清单并逐项映射任务；测试 env 开关改 `XCTSkip`（T108a）。
- LOW：golden (b) iOS 行来源、`ModelLoadingStartControlling` 转发、文件计数以 `module-map.json` 为准。

## 12. 待 Owner 决策

| # | 问题 | 选项（推荐在前） | 影响 |
|---|---|---|---|
| Q1 | 各阶段 PR 由谁执行 | (a) Dev Team issue（Owner 计划需要一个 Dev Team 来源的真实 PR 样本）；(b) subagent | PR-1 起的派发方式 |
| Q2 | 导出历史中的已知命中：作者个人邮箱、提交信息中的内部 issue 号、测试历史中的 Azure 资源主机名 | (a) 导出时 `--mailmap` 改 noreply + `--replace-message` 去内部号 + `--replace-text` 换主机名（只改导出历史，VoxPocket 不动）；(b) 保留（这些已在公开的 VoxPocket 历史中）；(c) 只导出阶段 1 起的 `Packages/VoxKit` 历史 | US6-AC1/AC2；(c) 与「保留历史」冲突 |
| Q3 | WhisperKit 隔离级别 | (a) 独立 product（不编译不链接，但 SPM 仍解析下载）；(b) 独立包，完全不解析 | US2-AC5；(b) 多一个发布单元 |
| Q4 | 意图/语气分析今天**不影响精炼输出**（结果被丢弃）。阶段 3：(i) 保留并同层并发（RB-12 排序放宽）(ii) 保留且串行 (iii) preset 默认去掉分析（行为变化，另立 spec） | (i) | §3.4、RB-12 |
| Q5 | 阶段 3 是否拆为两个 PR（SDK / App） | (a) 一个 PR 两组 commit（默认，符合一阶段一 PR）；(b) 拆 | §5 |
| Q6 | 首个 tag | (a) `0.1.0`（API 未稳定）；(b) `1.0.0` | 升级节奏、`ai/COMPATIBILITY.md` |
| Q7 | RB-2 删除 `LocalWhisperRawOutputLogger` 及其两个测试（测试断言的正是把 Whisper 原始输出写进日志） | (a) 删除并替换为「不记录内容」断言；(b) 仅 DEBUG 本机保留 | 宪法 IV；删除既有测试 |
| Q8 | PR-1 开工时若 S3（shared-ci caller、iOS 非 required lane、删 iOS 暂停）未合并 | (a) PR-1 等 S3；(b) PR-1 自带 lane 与表述修改 | 依赖顺序 |
| Q10 | Plan-Review Loop 在 3 轮上限结束，第 3 轮修订（N1–N3）未经 reviewer 复审 | (a) PR-1 开工前由 Dev Team 的 AI Reviewer 对本 plan 做一次 spec/plan 关复审（推荐）；(b) Owner 审阅即视为通过 | 本 plan 的放行条件 |
| Q9 | 阶段 PR 用 merge commit 保留逐层 commit 与 mv 历史，需 `auto-merge.yml` 对 `preserve-history` 标签例外 | (a) 同意（PR-0b）；(b) 保持 squash，接受阶段 2 起跨模块历史只靠相似度检测、「一层一 commit」只在 PR 分支可见 | C1、US6-AC1 |
