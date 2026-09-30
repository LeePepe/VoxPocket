# VoxKit 拆分调研

日期：2026-09-24。在线资料于当日通过 GitHub API 与 raw 文件核实（链接见各节）。

## R-1 Workflow 引擎选型

### 需求

- 默认流程 `capture → transcribe → [merge] → analyze(intent ∥ tone) → refine → output`，需要：DAG、同层并发、流式节点（转写 partial、精炼 chunk）、按节点失败策略（回退/默认值）、结构化取消、Codable 定义（JSON 编辑）、Swift 6 严格并发、macOS 26 + iOS 26、无服务端、依赖轻。

### 候选与核实结果

| 候选 | 核实到的事实 | 结论 |
|---|---|---|
| Square `workflow-swift` | 自述为「composable state machines, and UIs driven by those state machines」「unidirectional data flow…state-machine driven UI and navigation」；核心协议 `Workflow<Rendering, Output>` 以 `render(state:context:)` 渲染；v6.0.1（2026-08-25），Apache-2.0；manifest 依赖 ReactiveSwift、RxSwift、swift-syntax、swift-case-paths、swift-perception 等（按 target 使用） | **不采用**。面向 UI 状态树与渲染循环，不是数据流 DAG；无 JSON 定义；依赖面大。 |
| `apple/swift-async-algorithms` | 1.1.5（2026-06-29），Apache-2.0，3.7k stars；提供 `merge`、`combineLatest`、`zip`、`chain`、`AsyncChannel`/`AsyncThrowingChannel`（背压）、`debounce`/`throttle`、`chunks`、集合收集等 | **采用为积木**。流合并与背压通道正好服务流式节点；已经是 LLMKit 的依赖，不增加依赖。它不提供 DAG 调度。 |
| Temporal（`apple/swift-temporal-sdk`） | MIT，活跃；README 需要 `temporal server start-dev` 与服务器主机名 | **不采用**。需要常驻服务端，是持久化工作流引擎，不适合端上实时语音。 |
| LangChain Swift（`buhe/langchain-swift`） | 自述 beta；最新 release 0.46.0 在 2024-01-26；最后 push 2025-09 | **不采用**。成熟度与维护不足，抽象面向 RAG/agent，与语音流水线不匹配。 |
| ProcedureKit | MIT；最后 release 5.2.0（2019-04-03），最后 push 2022-12 | **不采用**。基于 `Operation`，早于 Swift Concurrency，已停更。 |
| `fireblade-engine/graph` | MIT，11 stars；最后 release 1.4.0（2023-04） | **不采用**。只是 DAG 数据结构，无执行器。 |
| `swift-composable-architecture` | MIT，活跃 | **不采用**。UI 状态管理框架，同 workflow-swift 的定位。 |
| 其他 | GitHub 搜索 `topic:dag`、`topic:workflow-engine`、`topic:pipeline`（language:swift）只找到应用或 Postgres 持久化引擎（`thoven87/strand`，需 Postgres） | 无成熟、端上、Concurrency 原生的 Swift DAG 执行库。 |

### 结论

自研轻量引擎：**Swift Concurrency（`TaskGroup`、`AsyncThrowingStream`）+ `swift-async-algorithms`（`merge`、`AsyncThrowingChannel`）**。预算约 400–600 行（不含内置节点与 preset），拆为 `Definition`（Codable 模型 + 校验）、`Registry`（id → 工厂）、`Scheduler`（拓扑分层 + TaskGroup）、`Events`（统一事件流）、`DSL`（result builder）、`Presets` 六个文件，每个文件 < 200 行。与需求稿初判一致。

### 来源

- https://github.com/square/workflow-swift （README、`Package.swift`、`Workflow/Sources/Workflow.swift`；releases v6.0.1 / v6.0.0）
- https://github.com/apple/swift-async-algorithms （README「Contents」一节；release 1.1.5）
- https://github.com/apple/swift-temporal-sdk （README 的 dev server 步骤）
- https://github.com/buhe/langchain-swift （release 0.46.0）
- https://github.com/ProcedureKit/ProcedureKit （release 5.2.0）
- https://github.com/fireblade-engine/graph （release 1.4.0）

## R-2 代码现状（基线 `afec620`）

| 项 | 事实 |
|---|---|
| 规模 | TranscriptionKit 25 文件约 4.0k 行；LLMKit 16 文件约 2.2k 行；测试 TranscriptionKitTests 50、LLMKitTests 24 个用例 |
| LokiKit 耦合 | 7 个 TranscriptionKit 文件、4 个 LLMKit 文件、4 个 PlatformAdapters 文件 `import LokiKit`；使用 `Logger` 协议（`log(_:_:context:…)`、`performanceStart/End`）、`PrintLogger`（22 处，其中约 10 处为默认参数）、`TelemetryService`/`NoopTelemetryService`（WhisperKit）、`TelemetryEventName` |
| 日志调用 | SDK 候选中约 114 处 logger 调用，其中 39 处字符串插值；内容泄漏见 spec KI-1 |
| env / 文件 | SDK 候选源码无 `ProcessInfo` / env 读取；文件操作：临时 WAV 创建/删除、`Data(contentsOf:)` 读自己写的 WAV、WhisperKit 模型缓存目录。env 与 `config.private.json` 只在 App 壳 `LLMAppConfig` 与 Preferences 的 loader |
| Combine | 12 个 TranscriptionKit 文件与 `LLMService` 协议 `import Combine`；Combine 只在转写侧 publisher 与状态上；LLM 已是 `AsyncThrowingStream` |
| VoxDomain 耦合 | 两个 kit 都 `import CoreModels`，只用 `VoxError`（28 处）与 1 处 `Session` 同名嵌套类型（`HybridRecordingLifecycle.Session`，与 domain 无关） |
| 跨 kit | LLMKit → TranscriptionKit（`TranscriptionResult`/`TranscriptionResultType`、`TranscriptionMerger`）；`LLMProvider` 协议要求 `analyze`/`refine`，provider 依赖 `IntentAnalysis`/`ToneAnalysis`/`AnalysisStep`/`RefinementPromptBuilder`；`HybridWhisperTranscriber` 依赖 `TranscriptionMerger` 协议。因此共享值类型与 merger 协议必须在最底层模块（plan §2.1） |
| 合并方式 | `auto-merge.yml` 对非 draft PR 挂 `--squash --auto`；ruleset 允许 squash/merge/rebase |
| CI 覆盖 | CI 不跑 `VoxPocketTests`（只有若干 `scripts/tests/*.py` harness 编译部分 App 壳文件）；`.gitignore` 忽略 `Package.resolved` |
| 分析结果的用途 | `analyzeContent` 的结果**不进入精炼 prompt**；`refineStreaming` 直接丢弃（`_ = await analyzeContent`）；App/Application/Presentation 无任何代码读取 `intentAnalysis`/`toneAnalysis`/`missingAnalysisSteps`。分析目前只产生延迟、provider 调用与日志。golden trace 必须记录「分析调用发生与否、调用顺序、选用 provider」，否则「行为不变」无法被证伪 |
| 流程写死 | `DefaultLLMService.analyzeContent`（分组顺序执行）、`HybridWhisperTranscriber.finishRecording`（realtime→batch→merge）、`ServiceContainer.injectMergerIfNeeded`、`StageModelRouting.resolveTranscriber` |
| 使用方 | VoxApplication 5 个源文件、VoxPresentation 8 个源文件、App 壳 5 个文件 import 两个 kit；kit 以外 12 个测试文件（Application 3、Presentation 7、App 2）import 两个 kit；`scripts/tests/test_realtime_config.py` 以 path 依赖编译 App 壳配置文件 |
| 平台 | `MicrophoneRecorder` 已有 `#if os(iOS)` 的 `AVAudioSession`；缺中断/路由变化处理与 `setActive(false)`；realtime 配置在 iOS 由 App 的 `LLMAppConfig.realtimeTranscriptionConfig`（`#if os(macOS)`）置为 nil，kit 本身无 iOS 排除 |
| 授权 | `SFSpeechRecognizer.requestAuthorization` 为静态调用，在 `AppleSpeechTranscriber`、`HybridWhisperTranscriber`、`HybridLocalWhisperTranscriber` 中共 6 处；macOS `AVCaptureDevice.requestAccess(for: .audio)` 在 `MicrophoneRecorder.requestPermission` 与 `startIfAllowed` 内部调用。无注入点，因此 golden (c) 需要 plan §3.1a 的授权接缝 |
| Combine 适配 | publisher 由实现类的 `private` subject 驱动（`WhisperKitTranscriber`、`HybridLocalWhisperTranscriber`、`LoadingFallbackTranscriptionCoordinator` 等），`ModelLoadingObservable` conformance 以同文件 extension 实现；跨 target 的 extension 无法访问，适配器必须是只用 public async API 的包装类（plan §2.2） |
| 模型缓存清理 | `WhisperKitTranscriber.resetCorruptedCache` 在快照损坏时删除 `huggingFaceWhisperKitRepoCacheCandidates()`（`cachesDirectory` 下与 macOS `~/.cache` 下的 HuggingFace 缓存）；删除路径解析时须由宿主注入同一结果（`VoxStorageLocations.modelCacheCleanupCandidates`） |
| iOS App 路由 | iOS 的转写器选择与 LLM 配置在 App 壳 `ServiceContainer` 的 `#else` 分支：batch 配置有→`HybridWhisperTranscriber`（realtime nil），否则 `AppleSpeechTranscriber` + warning；provider 未存→`LLMAppConfig.defaultProvider = .azureFoundry`；intent/tone 固定 `appleIntelligence`（`analysisProviderOverrides`）。`VoxPocketTests` 的 target 支持 iOS，但 CI 今天不跑 |
| iOS CI | `App target` job 已有 `Build app — iOS (no signing)` 步骤，最近 main run 成功；SPM 包只在 macOS 上 `swift build/test`，无 iOS Simulator 测试 |
| 历史 | 两个 kit 的源与测试路径自始至终在 `Packages/VoxInfrastructure/{Sources,Tests}/{TranscriptionKit,LLMKit}*`，共 30 个提交触及；作者邮箱为 Owner 个人邮箱；1 个提交信息含内部 issue 号；测试 diff 历史中出现 Azure 资源主机名。当前树另有 3 个文件含内部 issue 号（App 测试注释、`scripts/ci` 注释、基准测试 README），由 PR-0c 清理（Owner Q2） |

## R-3 SwiftPM 可选重依赖

SE-0226（部分实现于 Swift 5.2）：不被任何所用 product 涉及的依赖 target 不会被构建；但依赖**解析**仍按包进行。因此 `VoxSpeechWhisperKit` 作为独立 product 可保证只用 `VoxSpeech` 的消费者**不编译、不链接** WhisperKit，但 `Package.resolved` 仍会含 WhisperKit 条目并下载其源码。若 Owner 要求「完全不解析」，需把 WhisperKit 适配器放进第二个包（同 repo 子目录或独立 repo），见 plan §12 Q3。

来源：https://github.com/swiftlang/swift-evolution/blob/main/proposals/0226-package-manager-target-based-dep-resolution.md

## R-4 拆仓工具

本机已装 `git-filter-repo`。VoxKit 暂存包在阶段 2 通过 `git mv` 从 `Packages/VoxInfrastructure/...` 迁入 `Packages/VoxKit/...`；filter-repo 同时保留新旧路径并做 `--path-rename`，导出 main 可达的迁移前后历史（见 plan §9）。Owner 后续撤销 Q9，接受 squash 后历史：逐层 mv/edit commit 仍用于 PR 审查，但不承诺出现在 main 或导出仓；squash 可能令 `git log --follow` 无法跨改名。按 spec US6-AC1 用来源 SHA、路径映射、阶段 PR 的 squash SHA 与 filter-repo commit-map 保留可核验关联，最终树一致性与全导出历史隐私预检仍必需。
