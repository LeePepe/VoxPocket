# VoxKit 拆分计划（S6）

- Spec：[`spec.md`](./spec.md) · 任务：[`tasks.md`](./tasks.md) · 调研：[`research.md`](./research.md)
- 模式：`repo-kit split`（切接缝 → 搬迁 → 补齐能力 → 拆 repo → 新 repo `init` → 原 repo `adopt`）
- 前置：Owner 执行顺序中 VoxKit 步骤（S6）排在「VoxPocket 按 shared-ci 合同改造（S3）」与「零知识测试（S5）」之后；PR-1 等 S3 合并后开工（§12 Q8）。
- 执行方：阶段 1 起的阶段 PR 由 Dev Team 执行；Multica 不可达期间由 subagent 执行（§12 Q1）。
- 状态：§12 Q1–Q10 已由 Owner 决定（2026-09-24）；本修订经一轮独立复核（§11 第 4 轮）后，以 Owner 审阅为最终放行（Q10）。

## 1. 总则

1. **一阶段一 PR，一层一 commit**。commit 的「层」= 一个 SPM package（`VoxKit`、`VoxInfrastructure`、`VoxApplication`、`VoxPresentation`）、App 壳 `VoxPocket/VoxPocket/**`（含 `VoxPocketTests`、`project.yml`）、`docs/**`+`.specify/**`、`scripts/**`、`.github/**`。每个 commit 都能独立 build/test（pre-commit 按层增量验证，不用 `--no-verify`）。
   - **Owner 批准的例外（§12 Q5）**：AGENTS.md 要求跨 2+ layer 的任务按 layer 拆成独立子任务。阶段 PR 一个 PR 跨多层，这是 Owner 批准的例外；每个 commit 仍只改一层（E1/E2 除外），阶段 3 也只开一个 PR（SDK 组 commit 在 App 组之前）。
   - **构建规则**：每个 commit 必须能 build/test **本层及其所依赖的层**；下游层可以在同一 PR 内、直到其消费方 commit 之前暂时编译失败（例外 E3），**PR head 必须全绿**。pre-commit 只验证暂存的层，因此 E3 由 PR 的 CI 兜底；合并用 merge commit，这些中间 commit 会进入 `main`，`git bisect` 时用 `--first-parent`。
   - **已知例外**（每处在 PR 描述中列出）：(E3) 1.5–1.10（kit 初始化参数由 `Logger` 改为 `VoxLogger`，App 在 1.10 跟上）、2.1–2.7（模块改名无法 shim）、3.8–3.10（Application 在 3.9 改接口，App 壳在 3.10 跟上）；(E1) 阶段 2 的搬迁 commit 同时改 `Packages/VoxKit` 与 `Packages/VoxInfrastructure/Package.swift`，否则无法构建；(E2) 阶段 4 adopt 时所有 manifest 在同一 commit 从 path 切到 url（SwiftPM 不允许同一 package identity 既是 path 又是 url）；(E4) 测试 harness 与被测层同 commit：1.0b、1.0c、1.10 连带改 `scripts/tests/`，1.11 连带提交仓根 `VoxKitSDK.xcworkspace`/test plan 与 `scripts/verify`（CI lane 与其调用入口必须同时出现，否则该 commit 的 CI 无法运行）。
2. **历史保留的合并方式**：`auto-merge.yml` 会对非 draft PR 挂 squash auto-merge；squash 会抹掉「一层一 commit」与阶段 2 的「纯 mv commit」，导致 filter-repo 后丢失跨目录历史。因此：**PR-0b** 先给 `auto-merge.yml` 增加「带 `preserve-history` 标签的 PR 不挂 auto-merge」，并监听 `labeled` 事件：打标签时执行 `gh pr merge --disable-auto`；同时更新 AGENTS.md 与 CLAUDE.md「Git Workflow」中「所有 PR squash auto-merge」的表述；阶段 PR 均打 `preserve-history` 与 `owner-review`，Owner approve 后用 **merge commit**（`gh pr merge --merge`，ruleset 已允许 `merge`）合并。`git log --follow` 证据在合并后于 `main` 上采集。这是 policy 变更，Owner 已批准（§12 Q9）。
3. **行为不变到阶段 3 结束**：阶段 1、2 只做结构调整；阶段 3 用 workflow 替换写死的流程，由 golden 证明等价。spec §6 的 RB 项是唯一例外，每项单独 commit，并在 PR 的「Removed or weakened tests or policy」段逐条列出。
4. **Golden 先行**：阶段 1 最先的三个 commit 是「注入接缝（零行为变化）」「golden 基线（SPM）」「golden 基线（App iOS 行）」（1.0a–1.0c，§3.4）。
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
| `VoxCore` | 阶段 1：`VoxKitError`、`VoxLogger`/`VoxLogField`/`VoxLabel`、`VoxTelemetry`/`VoxTelemetryEvent`、`CredentialProvider`/`CredentialKey`、`VoxStorageLocations`、Noop 实现（**只有这些**，都不引用 kit 类型）。阶段 2（2.1 从 TranscriptionKit mv 入）加入共享值类型与跨模块协议：`TranscriptionResult`、`TranscriptionResultType`、`AudioCaptureState`、`ModelLoadingState`、`TranscriptionMerger` 协议、`mergedTranscription(...)`，`ASRProviderType`（1.6 从 `SpeechRecognitionService.swift` 拆出为 `ASRProviderType.swift`），以及 1.6 在 TranscriptionKit 新建的无 Combine 协议文件：`SpeechSession`/`TranscriptionEvent`、`SpeechSessionSource`、`SpeechSessionFactory`、`ModelLoadingStateProviding`、`ModelLoadingStartControlling` | 无 |
| `VoxSpeech` | 采集（`MicrophoneRecorder` → `MicrophoneCapture`）、Apple Speech、Azure batch（`WhisperEngine`/`AzureWhisperTranscriber`）、Azure realtime（`Realtime*`）、`HybridWhisperTranscriber`、`HybridRecordingLifecycle`、`DefaultSelectableTranscriptionCoordinator` 的 async 核心；1.0a 的注入接缝协议（§3.1a，`package` 可见） | VoxCore |
| `VoxSpeechWhisperKit` | `WhisperKitTranscriber`、`HybridLocalWhisperTranscriber`、`LocalWhisperKitConfig`、`LoadingFallbackTranscriptionCoordinator`、engine pool | VoxSpeech, WhisperKit |
| `VoxRefine` | 纯值与纯函数：`RefinementType`、`RefinementPromptBuilder`、`RefinementRequest`/`RefinementResponse`、`TranscriptionMetadata`、`IntentAnalysis`/`IntentType`/`FastIntentAnalysis`/`ToneAnalysis`/`AnalysisModels`（含 `AnalysisStep`/`AnalysisRequest`/`PartialAnalysis`） | VoxCore |
| `VoxLLM` | `LLMProvider`/`LLMService` 协议（async 形状）、`LLMProviderConfig`、`AppleIntelligenceProvider`、`AzureFoundryProvider`、`DefaultLLMService`（阶段 3 后变 internal）、`LLMTranscriptionMerger` | VoxCore, VoxRefine, AsyncAlgorithms |
| `VoxWorkflow` | 引擎与内置节点/preset（阶段 3） | 见图 |
| `VoxWorkflowWhisperKit` | 本地 WhisperKit 的节点与 preset（阶段 3） | 见图 |

与需求稿的差异：`LLMTranscriptionMerger` 放 `VoxLLM`（它依赖 `LLMService`），`VoxRefine` 只保留无 I/O 的 refine 类型与 prompt；这样 provider 可依赖 prompt 构建而不成环。

**类型级映射，一文件一目的地**：阶段 1（1.6）先把混合文件拆开，使每个文件只含去往同一模块的类型：`TranscriptionMerger.swift` 拆出 `MultiRecognizerTranscriber.swift`（Combine 形状，进 `TranscriptionKitCombine` target，§2.2）；`AudioCaptureService.swift` 拆出 `AudioCaptureState.swift`（去 VoxCore）；`SpeechRecognitionService.swift` 拆出 `ASRProviderType.swift`（核心类如 `AzureWhisperTranscriber` 仍用它，去 VoxCore）；`ModelLoadingObservable.swift` 拆出 `ModelLoadingStartControlling.swift`（无 Combine，去 **VoxCore**：`DefaultRecordingUseCase.resolveCoordinatorForStart` 对任意 coordinator 做 `as? any ModelLoadingStartControlling`，VoxApplication 不应为此依赖 `VoxSpeechWhisperKit`）。1.6 同时在 TranscriptionKit 新建**无 Combine** 文件 `SpeechSession.swift`（`SpeechSession`、`TranscriptionEvent`）、`SpeechSessionSource.swift`、`SpeechSessionFactory.swift`、`ModelLoadingStateProviding.swift`：它们引用的 `TranscriptionResult`、`AudioCaptureState`、`ModelLoadingState` 阶段 1 仍在 TranscriptionKit，所以阶段 1 声明在 TranscriptionKit（同 target，无环），`module-map.json` 把它们映射到 VoxCore，2.1 随 `TranscriptionResult` 等一起 mv 入 VoxCore。1.6 同时加检查脚本 `scripts/redlines/module-map.py`：读 `module-map.json`（文件→目的模块），断言每个 kit 文件恰有一个目的地、目的模块的依赖闭包包含该文件用到的所有类型所在模块（按 import 与类型名粗检）；阶段 1 就断言「映射到 VoxCore 的文件只引用映射到 VoxCore 的类型」，从而在 mv 之前证明 VoxCore 无环。**import 预置（保证 2.1 的纯 mv commit 可构建）**：1.6 给每个使用 VoxCore 映射类型的 kit / `TranscriptionKitCombine` / LLMKit 文件预先加 `import VoxCore`（阶段 1 VoxCore 已存在，该 import 合法；例：`DefaultSelectableTranscriptionCoordinator.swift`、`LoadingFallbackTranscriptionCoordinator.swift`、`LLMKit/Models/TranscriptionMetadata.swift` 今天没有 LokiKit import，不会被 1.5 顺带改到），同理给使用 VoxSpeech 映射类型的 WhisperKit 文件与 LLMKit 文件保留 `import TranscriptionKit`；`module-map.py` 检查「文件用到的每个目的模块都已被 import（或同模块）」。脚本位置：`Packages/VoxKit/scripts/redlines/module-map.py`（与 `check.sh` 同处，随拆仓迁移；阶段 4 后只剩自检用途）。

文件→模块映射（阶段 2 的 mv 清单，即 `module-map.json`）：TranscriptionKit 文件（数量以 `module-map.json` 为准）中，`TranscriptionResult`、`TranscriptionMerger`（仅协议与 `mergedTranscription`）、`AudioCaptureState`、`ModelLoadingState`、`SpeechSession`（含 `TranscriptionEvent`）、`SpeechSessionSource`、`SpeechSessionFactory`、`ModelLoadingStateProviding`、`ModelLoadingStartControlling` → VoxCore；`WhisperKitTranscriber`、`HybridLocalWhisperTranscriber`、`LocalWhisperKitConfig`、`LoadingFallbackTranscriptionCoordinator`、`ModelPreloadControlling` → VoxSpeechWhisperKit；其余 → VoxSpeech。`TranscriptionKitCombine` target 的文件**不在** `module-map.json` 中（它们从不进 VoxKit，2.4 整体 mv 进 `VoxKitBridge`）。LLMKit：`Models/*`、`Utilities/RefinementPromptBuilder` → VoxRefine；`Protocols/*`、`Providers/*`、`Services/*`、`LLMTranscriptionMerger` → VoxLLM。**非移动的改动**（import、access level）只在紧随的 edit commit 中，不与 mv 同 commit。

### 2.2 Combine 与 async 的归属（M2）

| 类型 | 阶段 1 | 阶段 2 起 |
|---|---|---|
| `TranscriptionCoordinator`、`AudioCaptureService`、`SpeechRecognitionService`、`MultiRecognizerTranscriber`、`ModelLoadingObservable`（Combine 形状） | 1.6 起放进 VoxInfrastructure 的**独立 target `TranscriptionKitCombine`**（`Sources/TranscriptionKitCombine/`，依赖 `TranscriptionKit`，TranscriptionKit 不依赖它） | 2.4 把整个 target 目录 `git mv` 进 `VoxKitBridge/Combine/`（纯 mv + import edit），形状与签名不变 |
| 协议文件 `TranscriptionCoordinator.swift`、`AudioCaptureService.swift`（拆出 `AudioCaptureState` 后的剩余部分）、`SpeechRecognitionService.swift`、`ModelLoadingObservable.swift`、`MultiRecognizerTranscriber.swift` | 1.6 中**整文件** mv 入 `TranscriptionKitCombine` | 随该 target 进 Bridge |
| Combine 适配器（**独立包装类，不是 extension**） | 今天的 publisher 由实现类的 `private` 存储 subject 驱动（如 `WhisperKitTranscriber` 的 `liveResultSubject`/`_modelLoadingStateSubject` 与 `extension WhisperKitTranscriber: ModelLoadingObservable`，`LoadingFallbackTranscriptionCoordinator` 的四个 subject），跨 target 的 extension 访问不到它们。因此 1.6 在 `TranscriptionKitCombine` 中新建包装类，只用核心的 **public async API**（`SpeechSessionSource.startSession(language:)` → `SpeechSession.events()`、`ModelLoadingStateProviding.modelLoadingStates()`），自己持有 `PassthroughSubject`/`CurrentValueSubject` 并从 async 流泵入；今天 Combine 协议面向消费者暴露的每一项都由 `SpeechSessionSource` 提供（§2.4）：`supportedLanguages`、`providerKind`（`ASRProviderType`）、麦克风与语音**分开**的权限查询/请求、会话开始**之前**即可订阅的 `captureStates()`/`audioLevels()`（`DefaultRecordingUseCase` 在 `start` 前订阅）、`isActive`；同步 `pause()`/`resume()` 由包装类在一个串行 `Task` 队列中按调用顺序转为 `await session.pause()/resume()`，事件仍经同一有序流转发（golden (c) 增加 pause/resume 用例）；`CombineTranscriptionCoordinator`（`TranscriptionCoordinator`）及其子类 `CombineMultiRecognizerCoordinator`（+`MultiRecognizerTranscriber`，`merger` 转发到核心的 `MergerConfigurable.merger`）、`CombineLoadingCoordinator`（+`ModelLoadingObservable`、`ModelLoadingStartControlling`）、`CombineMultiRecognizerLoadingCoordinator`（两者皆有）；`CombineTranscriptionCoordinator.wrap(_ core:)` 按核心的运行时 conformance 选子类：`ModelLoadingObservable` 当且仅当核心实现 `ModelLoadingStateProviding`，`ModelLoadingStartControlling` 当且仅当核心实现 `ModelLoadingStartControlling`（**逐协议独立判定**，例如 `WhisperKitTranscriber` 今天只有前者，`HybridLocalWhisperTranscriber` 两者皆有，因此加载相关子类分「仅 `ModelLoadingObservable`」与「`ModelLoadingObservable` + `ModelLoadingStartControlling`」两种，再按是否 `MultiRecognizerTranscriber` 区分；只实现今天实际出现的组合，Bridge 测试列出组合表），使 `as? any ModelLoadingObservable`/`as? any ModelLoadingStartControlling`/`as? any MultiRecognizerTranscriber` 的结果与今天逐类型相同（Bridge 测试逐类型断言这张 conformance 表）；`merger` 转发到核心的 `MergerConfigurable`（`protocol MergerConfigurable: AnyObject, Sendable { var merger: (any TranscriptionMerger)? { get set } }`，阶段 1 在 TranscriptionKit，映射 VoxSpeech，`package` 可见性，不进公共 API）；另有 `CombineModelLoadingObservable` 包装任意 `ModelLoadingStateProviding`（供 `ServiceContainer.localModelLoadingObservable`）。核心类删除所有 subject 与 Combine conformance | 2.4 纯 mv，无需改写 |
| 模型加载状态 | 新增 SDK 侧 async 协议 `ModelLoadingStateProviding { var modelLoadingState; func modelLoadingStates() -> AsyncStream<ModelLoadingState> }`（阶段 1 在 TranscriptionKit，2.1 进 VoxCore）；`LoadingFallbackTranscriptionCoordinator` 与 `WhisperKitTranscriber` 的 `as? any ModelLoadingObservable` 改为 `as? any ModelLoadingStateProviding`；`TranscriptionKitCombine` 的包装类适配为 `ModelLoadingObservable` | SDK 不依赖 Bridge |
| `DefaultSelectableTranscriptionCoordinator`、`LoadingFallbackTranscriptionCoordinator` | 改为 async 核心（实现 `SpeechSessionSource`，组合其他 `SpeechSessionSource`），Combine 形状由上述包装类提供；`factory` 闭包改为 `Sendable` 工厂协议 `SpeechSessionFactory` | 同上 |
| `MicrophoneRecorder.start(bufferHandler:)` | 改为返回 `AsyncStream<AVAudioPCMBuffer>`（buffer 由内部有界通道转发）或降为 `package`；VoxSpeech 内部消费 | — |
| `LLMService`、`DefaultLLMService`（`import Combine` 但无 publisher） | 删除无用 `import Combine` | 在 VoxLLM |
| `TranscriptionResult` 及引用它的新协议（`SpeechSession`/`TranscriptionEvent`/`SpeechSessionSource`/`SpeechSessionFactory`/`ModelLoadingStateProviding`） | 仍在 TranscriptionKit（阶段 1 **不移动文件**；VoxCore 不重复定义，也不引用它们） | 2.1 mv 到 VoxCore |
| `VoxError` 的 kit 相关 case | kit 改抛 `VoxKitError`（新类型在 VoxCore） | — |

R4（无 Combine 公共 API）在阶段 1 覆盖 `Packages/VoxKit/Sources` 与两个 kit 的全部文件（Combine 已在独立 target `TranscriptionKitCombine`，不在扫描范围）；阶段 2 起覆盖整个 `Packages/VoxKit/Sources`。R1–R3 覆盖 **Sources**（阶段 1：`Packages/VoxKit/Sources` 与两个 kit 的 Sources；阶段 2 起：`Packages/VoxKit/Sources`）；R5 额外覆盖 Tests 与 Examples（今天 `WhisperEngineRequestTests` 含 `VoxPocket` 字样，在 KI-4 commit 中修正）。测试代码的 env 开关（`GuidedGenerationTests` 的 `VOX_RUN_GUIDED_GENERATION_TESTS`）与 `print` 不属于 SDK 发布面，不受 R1/R3(b) 约束，但阶段 4 前改为 `XCTSkip` + test plan 开关并移除内容打印（T108a）。**T105 先对当前代码跑一次全部规则，产出违规基线清单，每一项映射到一个任务**；GATE-1 要求清单清零。

### 2.3 App 侧

| Layer | 变化 |
|---|---|
| VoxDomain | 不变 |
| VoxInfrastructure | 阶段 1 新增 `TranscriptionKitCombine` target（Combine 协议与包装类，§2.2）与 `VoxKitBridge` target：`LokiVoxLogger`、`LokiVoxTelemetry`、`EnvironmentCredentialProvider`（包装已加载的 env/私密配置快照，不自行读取）。阶段 2：删除 TranscriptionKit/LLMKit target；2.4 把 `TranscriptionKitCombine` mv 进 `VoxKitBridge/Combine/` 并删除该 target。阶段 3：`StageModelSettings` → preset 映射、workflow 驱动的 `TranscriptionCoordinator` 与 refine runner |
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
public struct VoxStorageLocations: Sendable {
    public let temporaryAudio: URL
    public let modelCache: URL
    /// 模型缓存损坏时额外清理的目录（今天 WhisperKitTranscriber.huggingFaceWhisperKitRepoCacheCandidates 的结果），由宿主计算
    public let modelCacheCleanupCandidates: [URL]
}

// 以下协议 1.6 声明在 TranscriptionKit，2.1 mv 入 VoxCore（§2.1）
public enum TranscriptionEvent: Sendable {
    case partial(TranscriptionResult), final(TranscriptionResult)
    case level(Float), state(AudioCaptureState)
}
public protocol SpeechSessionSource: AnyObject, Sendable {
    var supportedLanguages: [Locale] { get }
    var providerKind: ASRProviderType { get }
    func requestMicrophonePermission() async -> Bool
    var hasMicrophonePermission: Bool { get }
    func requestSpeechPermission() async -> Bool
    var hasSpeechPermission: Bool { get }
    var isActive: Bool { get }
    /// 源级别、多消费者（每次调用返回新流，当前值先发），会话开始前即可订阅
    func captureStates() -> AsyncStream<AudioCaptureState>
    func audioLevels() -> AsyncStream<Float>
    func startSession(language: Locale) async throws -> any SpeechSession
}
public protocol SpeechSessionFactory: Sendable {
    func makeSource() async throws -> any SpeechSessionSource
}

public protocol SpeechSession: Sendable {
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error>   // partial / final / level / state
    func pause() async
    func resume() async
    func stop() async
    func cancel() async
}
public protocol ModelLoadingStateProviding: AnyObject, Sendable {
    var modelLoadingState: ModelLoadingState { get }
    func modelLoadingStates() -> AsyncStream<ModelLoadingState>
}
public protocol ModelLoadingStartControlling: AnyObject, Sendable {
    var blocksRecordingUntilModelReady: Bool { get }
}
```

阶段 3 的 workflow 有**两个入口**（对应 App 的两个用例）：`speech`（capture → transcribe → [merge] → final text）与 `refine`（text + customPrompt + metadata → analyze(intent ∥ tone) → refine → 流式 chunk）。一个 `Preset` = 一对 `WorkflowDefinition`（`speech`、`refine`），录音结束后由 App 把终稿（或用户编辑后的文本）作为 `refine` 的输入。

## 3. 阶段 1：仓内切接缝（PR-1）

**目标**：建 `Packages/VoxKit`（只有 VoxCore）；TranscriptionKit/LLMKit 原地从 LokiKit 改为 VoxCore 协议，内部改为 async 核心 + 隔离的 Combine 适配；App 壳实现适配器；SDK 相关代码 iOS Simulator 测试修绿后改为 required。行为不变（RB-1…RB-7、RB-11 除外）。

### 3.1 子任务（按 commit 顺序）

| # | 层 | 内容 |
|---|---|---|
| 1.0a | VoxInfrastructure | **注入接缝（零行为变化）**：见 §3.1a。`HybridWhisperTranscriber`/`HybridLocalWhisperTranscriber`/`AppleSpeechTranscriber`/`MicrophoneRecorder` 新增 internal init，接收 §3.1a 的录音源、识别器、批量转写、realtime 会话工厂与**授权提供者**；公开 init 转调并传入与今天完全相同的默认实现（`SFSpeechRecognizer.requestAuthorization`、macOS `AVCaptureDevice.requestAccess`/iOS `AVAudioSession.requestRecordPermission` 等调用只搬进默认实现，不改）。审查标准：公开 init 行为逐字不变，只加参数 |
| 1.0b | VoxInfrastructure/Tests + `scripts/tests`（E4） | **Golden 基线**（§3.4），在 1.0a 的代码上录制；`Package.swift` 新增 test target `GoldenTraceTests`，因此由现有 `SPM VoxInfrastructure` job 在 CI 上运行 |
| 1.0c | App 壳（`VoxPocketTests`）+ `.github`（E4） | golden (b) 的 iOS 行：新增 `VoxPocketTests/GoldenRoutingTests`（在 1.0a 代码上录制 iOS fixture 到 `scripts/tests/golden/`），并**提前**加入非 required 的 `App unit tests (iOS)` lane（与 1.11 同一命令与目的地；1.11 只再加其余 lane）。**闸门**：1.0a–1.0c 先推送到 Draft PR-1，CI 在 1.0c commit 上跑通 golden (c)（`SPM VoxInfrastructure`）与 golden (b) iOS 行（`App unit tests (iOS)`），两个 run 链接写入 PR 描述，之后才推送 1.1 起的任何 commit |
| 1.1 | docs/.specify | **修宪 1.2.0**（§8）+ 新增 `Packages/VoxKit/tech-context.md` 的 red_lines 投影 + 根 tech-context/AGENTS layer 表/dependency-graph 加 VoxKit + `scripts/gates/check_frontmatter.py` 识别 VoxKit 层（Governance：规则与 red_lines 同一变更，先于代码）。「iOS 暂停」表述由 S3 删除（Q8：PR-1 等 S3），本 commit 只核对 |
| 1.2 | VoxKit | 新包：VoxCore（§2.4，`VoxKitError.errorDescription` 与 `VoxError` 对应 case 逐字相同）、`VoxCoreTests`、Swift 6 语言模式、iOS 26/macOS 26 |
| 1.3 | VoxKit | `scripts/redlines/`：R1–R5 检查 + 每条规则的负例 fixture + 正例 fixture + `--self-test`（§6，含编译型 fixture 的诊断文本匹配） |
| 1.4 | VoxKit | 隐私金丝雀测试工具（`CanaryLogger`/`CanaryTelemetry`，供两个 kit 与后续 VoxWorkflow 使用） |
| 1.5 | VoxInfrastructure | 按文件分组的多个 commit：`import LokiKit` → `import VoxCore`；`Logger` → `VoxLogger`；插值日志 → `StaticString` + 字段（RB-4）；RB-1、RB-2（Q7：删除 `LocalWhisperRawOutputLogger` 与 `LocalWhisperRawOutputLoggerTests`，新增「日志不含转写」测试）、RB-3、RB-5、RB-6 各一个 commit；`VoxPocket/TemporaryAudio`、`VoxPocketWhisperKitHub` 与 HuggingFace 缓存候选目录改由注入的 `VoxStorageLocations`（`temporaryAudio`/`modelCache`/`modelCacheCleanupCandidates`）提供（KI-4）；删 `CoreModels` 依赖；删无用 `import Combine` |
| 1.6 | VoxInfrastructure | 拆混合文件（含 `ASRProviderType`）+ 新建无 Combine 协议文件（§2.1）+ `import VoxCore` 预置 + `module-map.json` 与检查；async 核心（实现 `SpeechSessionSource`）；1.0a 接缝中的 `audioLevelPublisher`/`statePublisher` 在此改为 async 流（包装类之后）；新 target `TranscriptionKitCombine`：Combine 协议文件与**独立包装类**（§2.2，RB-7）；新 target `VoxKitBridge`（Loki 适配器、`EnvironmentCredentialProvider`）；VoxInfrastructure `Package.swift` 为 `TranscriptionKitCombine` 与 `VoxKitBridge` 各加 library product（VoxApplication/VoxPresentation/App 需要 `ModelLoadingObservable` 等，1.8/1.9 依赖之）。kit 测试中依赖 Combine 形状的用例（如 `LoadingFallbackTranscriptionCoordinatorTests` 的 `FakeLoadingCoordinator`）改写为针对 async 核心 + 针对包装类两组，断言逐条等价，列入 PR 的「Removed or weakened tests」段并说明等价。可按 target 拆多个 commit，均属 VoxInfrastructure 层 |
| 1.7 | VoxInfrastructure | iOS 采集：`AVAudioApplication.requestRecordPermission`、停止时 `setActive(false, .notifyOthersOnDeactivation)`、中断/路由变化通知处理（RB-11）；合成音频源 |
| 1.8 | VoxApplication | import 调整（错误匹配如有） |
| 1.9 | VoxPresentation | import 调整 |
| 1.10 | App 壳 | `ServiceContainer` 构造并注入 `LokiVoxLogger`/`LokiVoxTelemetry`/`VoxStorageLocations`（值与今天路径相同：`temporaryAudio` = `Application Support/VoxPocket/TemporaryAudio`，`modelCache` = `Caches/VoxPocketWhisperKitHub`，`modelCacheCleanupCandidates` = 今天 `huggingFaceWhisperKitRepoCacheCandidates()` 的同一计算：`Caches/huggingface/hub/models--argmaxinc--whisperkit-coreml`，macOS 另加 `~/.cache/huggingface/hub/models--argmaxinc--whisperkit-coreml`；有测试逐项断言）/`EnvironmentCredentialProvider`；coordinator 经 `CombineTranscriptionCoordinator.wrap(_:)` 包装；`injectMergerIfNeeded`、`localModelLoadingObservable`、`TranscriberSelectionTests` 中的 `is HybridWhisperTranscriber` 等类型判断改为判断包装类的 `core`（断言强度不变）；`LLMAppConfig` 仍是唯一 env/私密配置读取点；`VoxPocketLogging.allowedMessages` 同步静态消息；`scripts/tests/test_realtime_config.py` 的临时包增加 `TranscriptionKitCombine`/`VoxKitBridge`/VoxKit 依赖（它把 App 壳文件编进临时包） |
| 1.11 | .github + 仓根 | CI 新增（非 required）：`SPM VoxKit`（macOS）；`iOS SDK`：`xcodebuild test -workspace VoxKitSDK.xcworkspace -scheme VoxKitSDK -testPlan VoxKitSDK -destination "$VOXKIT_IOS_DESTINATION"`，其中 `VoxKitSDK.xcworkspace`（仓根，只引用 `Packages/VoxKit` 与 `Packages/VoxInfrastructure`）、共享 scheme `VoxKitSDK` 与 `VoxKitSDK.xctestplan` 在本 commit 提交，test plan 只包含 `Packages/VoxKit` 与 VoxInfrastructure 的 TranscriptionKit/TranscriptionKitCombine/LLMKit/VoxKitBridge/GoldenTraceTests test targets，排除基准与 PlatformAdapters；`App unit tests`（`xcodebuild test -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -only-testing:VoxPocketTests -destination 'platform=macOS'`，无签名，覆盖 `TranscriberSelectionTests` 等今天 CI 未跑的测试）；`App unit tests (iOS)`（已在 1.0c 加入，本 commit 不重复；Owner Q6：App 与 VoxKit 都要 iOS build/test；产出 golden (b) 的 iOS 行，§3.4）；`iOS SDK` 与 `SPM VoxKit` job 与现有 `spm` job 一样 checkout LokiKit（VoxInfrastructure 依赖 `../../../LokiKit`）；`SDK red lines`（`Lint & policy` 内步骤，含 `--self-test`）。**Simulator 目的地固定**：`VOXKIT_IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=26.0'` 写在 workflow 顶层 `env` 与 `scripts/verify` 中，不用 `generic/`、`latest` 或 `OS` 缺省；1.11 实施时先在 `macos-26` runner 上用 `xcrun simctl list runtimes devices` 核实该组合存在，不存在则改为 runner 上存在的最低 iOS 26.x 与对应机型并同步两处 |
| 1.12 | scripts/rulesets | `main-protection.json` 加入 `SPM VoxKit`、`iOS SDK`、`App unit tests`、`App unit tests (iOS)`。**只改文件**；PR-1 合并后由 Owner 批准执行 `scripts/rulesets/apply`（先合并再 apply，避免其他 PR 等待 main 上尚不存在的 check） |

> PR-1 在 S3 合并后开工（Q8），因此 1.11 的 lane 以 S3 之后的 CI 形状接入（shared-ci caller 的 `quality.yml` build/test 输入），check 名按 S3 的映射；以当时 ruleset 为准，required 不减少。

### 3.1a 注入接缝（1.0a）的协议

全部为 TranscriptionKit 内 `internal`（阶段 2 进 VoxSpeech 后为 `package`），不进公共 API，不受 R4 约束；默认实现只搬运今天的调用，不改参数与顺序。

| 协议 | 形状 | 默认实现（今天的代码） | 替换的调用点 |
|---|---|---|---|
| `SpeechAuthorizationProviding` | `func requestSpeechAuthorization() async -> Bool`；`var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }` | `SFSpeechRecognizer.requestAuthorization` → `status == .authorized`；`SFSpeechRecognizer.authorizationStatus()` | `AppleSpeechTranscriber`、`HybridWhisperTranscriber`、`HybridLocalWhisperTranscriber` 中共 6 处 `requestAuthorization` 与各 `hasPermission` 中的 `authorizationStatus()` |
| `MicrophoneAuthorizationProviding` | `func requestMicrophoneAccess() async -> Bool`；`var hasMicrophoneAccess: Bool { get }` | macOS `AVCaptureDevice.requestAccess(for: .audio)`/`authorizationStatus`；iOS `AVAudioSession.requestRecordPermission`/`recordPermission` | `MicrophoneRecorder.requestPermission`、`hasPermission` 与 `startIfAllowed` 内的 `requestAccess` |
| `AudioBufferSource` | `func start(shouldStart: @escaping @Sendable () -> Bool, bufferHandler: ((AVAudioPCMBuffer) -> Void)?) async throws`；`func stop() -> URL?`；`pause()`；`resume()`；`var audioLevelPublisher: AnyPublisher<Float, Never>`；`var statePublisher: AnyPublisher<AudioCaptureState, Never>`；`var state: AudioCaptureState`（1.0a **保留 Combine 形状**，多订阅者与时序与今天相同；1.6 在包装类之后改为 async 流） | `MicrophoneRecorder`（其授权经 `MicrophoneAuthorizationProviding` 注入） | 三个 transcriber 的 `recorder` |
| `SpeechRecognizing` | `func recognitionTask(locale: Locale, request: SFSpeechAudioBufferRecognitionRequest, handler: @escaping (RecognitionUpdate) -> Void) throws -> any SpeechRecognitionTasking`；`RecognitionUpdate` = `{text, isFinal, confidence}` 或 `{errorDomain, errorCode}` | `SFSpeechRecognizer(locale:)` + `recognitionTask(with:)` | 三个 transcriber 的 `speechRecognizer` |
| `SpeechRecognitionTasking` | `finish()`、`cancel()` | `SFSpeechRecognitionTask` | `recognitionTask` 属性 |
| `BatchTranscribing` | `func transcribe(fileURL: URL, language: Locale) async throws -> String` | `WhisperEngine` | `HybridWhisperTranscriber.whisperEngine` |
| `RealtimeSessionMaking` | `func makePipeline(config: AzureRealtimeTranscriptionConfig, onPartial: @escaping @Sendable (String) -> Void) -> any RealtimePipelining`（`append`/`start(language:)`/`finish()`/`cancel()`） | `DefaultRealtimeTranscriptionSession` + `RealtimeAudioPipeline` | `HybridWhisperTranscriber.startRecording` 中的构造 |

1.0a 的接缝是 internal、仅供测试，阶段 1 内保留 Combine 形状不违反 R4（R4 只查 public/open 符号与 `import Combine`，1.6 之前 R4 尚未启用于这些文件，T105 基线清单把它们映射到 1.6）。Golden (c) 与 US5-AC2 的 iOS 采集测试都只经这些协议注入假实现，CI 上不触发任何系统授权弹窗或真实音频设备。

### 3.2 验收

- Golden（§3.4）相等：US1-AC1；US1-AC2、AC5、AC6、AC7。
- R1–R5 在阶段 1 范围（§2.2）通过，负例 self-test 通过：US2-AC2、AC3、AC4（阶段 1 范围）、AC6；US4-AC1、AC2、AC4。
- `iOS SDK` 与 `App unit tests (iOS)` lane 绿：US5-AC1（阶段 1 部分）、US5-AC2、US5-AC3。
- golden (c) 与 golden (b) iOS 行在 1.0c commit 上的 CI run 链接已写入 PR 描述（§3.1 1.0c 闸门）。
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
| (b) 纯逻辑 + App 路由（macOS 行由 harness 产出；iOS 行由 1.0c 的 `GoldenRoutingTests` 在 iOS Simulator 上产出，基线在 1.0a 代码上录制：iOS 的 `ServiceContainer.makeTranscriber`/`configureLLMService` 分支是 App 壳的 `#else` 代码，`iOS SDK` lane 不编译 App 壳，Python harness 只能 `swift test` 于 macOS） | `HybridRecordingLifecycle`、`RealtimeASRFinalizer`、`mergedTranscription`、`StageModelRouting.resolveTranscriber`/`resolvedSpeechModel`/`analysisOptions`、`DefaultStageTextModelService` 的配置失败语义；iOS：`ServiceContainer.makeTranscriber`（`.hybridWhisper` 的 `#else` 分支）与 `configureLLMService`/`applyProviderPreferenceIfExists`/`applyAnalysisSettingsPreference` 导出的 `pipeline` | TranscriptionKit 测试 + `scripts/tests/test_golden_routing.py`（仿 `test_realtime_config.py`，把 App 壳文件编进临时包，macOS）+ `VoxPocketTests/GoldenRoutingTests`（`App unit tests (iOS)` lane，与 harness 共用 `scripts/tests/golden/` 的 fixture） | EB-1 表全部行 × iOS/macOS 分支；EB-7 Azure 未配置；iOS 行：{batch 配置 有/无} × {`llm.provider` 未存/`azureFoundry`/`appleIntelligence`/非法值} × {`llm.skipContentAnalysis` 真/假} × {Azure 文本 有/无} × {偏好变更通知：改为合法值/改为非法值/删除} |
| (c) 端到端转写 | 1.0a 的注入接缝（§3.1a，含授权提供者，因此可在 CI 无弹窗运行） | `VoxInfrastructure/Tests/GoldenTraceTests/Speech*` | Hybrid × {realtime 成功, realtime 失败→batch, 静默跳过, 有/无合并器}；AppleSpeech × {授权拒绝, 成功}；麦克风授权拒绝；录音中 pause→resume；开始前订阅电平/状态；事件序列（类型、文本、顺序）；主/快捷两栈并行各一次 |

所有组都记录：遥测事件名与属性键、Loki 允许名单内的日志消息。

**`pipeline` 描述（跨阶段可比的中性表示）**：`golden-trace/v1` 含 `pipeline` 字段——`speech: [节点 kind…]`（如 `[capture.microphone, speech.apple, speech.azure.realtime, speech.azure.batch]`）、`realtime: bool`、`merger: bool`、`analysis: {intent, entities, tags, params, tone: provider|skipped}`（**逐步**：macOS 今天 entities/tags/params 跟随 intent〔`StageModelRouting.analysisOptions`〕，iOS 今天 intent/tone 固定 Apple 而 entities/tags/params 落到 refine provider〔`DefaultLLMService` 的 `analysisProviderOverrides[step] ?? defaultProviderType`〕，只记 intent/tone 会漏掉 iOS 的 Azure 分析调用）、`refine: provider`、`configFailure: none|textModelUnavailable`。基线时由 (b) 的探针从 `resolveTranscriber`/`resolvedSpeechModel`/`DefaultStageTextModelService` 的结果导出；阶段 3 起由 `Preset.default.overriding(StageModelSettings 映射)` 的定义导出；两者对 `StageModelSettings` 全组合 × {配置齐全, batch 缺失, realtime 缺失, Azure 文本缺失} 逐项相等。(c) 阶段 3 起：`Hybrid*Transcriber` 的核心逻辑成为 `speech.*`/`merge.llm` 节点的实现，1.0a 注入的同一组假识别器/录音源/`WhisperEngine`/realtime 工厂在节点边界注入，事件序列与基线比较。

**比较规则**：
- 同一 provider 内 intent 组先于 tone 组（今天由代码保证）→ 严格比较。
- **跨 provider 的分析组顺序今天就不确定**（`stepsByProvider` 是 `Dictionary`，每进程哈希种子不同）→ 从基线起就按 (provider, 步骤) 排序比较。
- 阶段 3 起同一层分析并发：同层调用按 (provider, 步骤) 排序比较（RB-12），其余字段逐项相等。
- RB-3 的 `reason` → `error_kind` 在其 commit 内同时更新基线（单独的 baseline-update 提交，列在 PR）。

**不覆盖**（如实声明）：真实麦克风、SFSpeechRecognizer 识别结果、AVAudioEngine 时序、真实网络、FoundationModels 输出。它们由既有集成测试与人工 TestFlight 使用覆盖。

**Fixture 位置**：阶段 1 在 `VoxInfrastructure/Tests/GoldenTraceTests/Fixtures`；阶段 2 起 (a)(c) 在 `Packages/VoxKit/Tests/GoldenTraceTests/Fixtures`，(b) 在 `scripts/tests/golden/`；两处共用的 `pipeline` 描述 fixture **复制**一份，`scripts/tests/check_golden_drift.py` 比较 schema 版本与内容哈希；阶段 4 后 drift 检查改为比较 App 侧副本与所 pin 版本 VoxKit tag 中的副本（T409）。

### 3.5 PR 边界

PR-1 = 1.0a–1.12（含 1.0c）。**不移动文件**。合并条件：required 全绿，Owner approve（修宪、RB-1…RB-7、RB-11、ruleset 文件）后 merge commit 合并；合并后 apply ruleset 并回读。

## 4. 阶段 2：搬迁（PR-2）

**目标**：按 §2.1 映射把 TranscriptionKit/LLMKit 源与测试 `git mv` 进 `Packages/VoxKit`；`TranscriptionKitCombine` target 整体 mv 进 `VoxKitBridge`；App 改为依赖 VoxKit。只移动与 import 调整，行为不变。

### 4.1 子任务

| # | 层 | 内容 |
|---|---|---|
| 2.1 | VoxKit + VoxInfrastructure/Package.swift（E1） | 按模块分组的 mv commit，**依赖序**：VoxCore → VoxSpeech+VoxSpeechWhisperKit（同一 commit：二者都来自 TranscriptionKit，分开会在同一包图中出现两个 `TranscriptionKit` 模块）→ VoxRefine+VoxLLM（同一 commit，同理来自 LLMKit）。每个 commit 只 `git mv` 并做**最小** manifest 修改使其可构建（VoxKit 内暂用原 target 名：`VoxCore` 用正式名，另两组用过渡名 `TranscriptionKit`/`LLMKit`；VoxInfrastructure 的 `TranscriptionKitCombine`/`VoxKitBridge` 等改为依赖 `../VoxKit` 的这些 product，原同名 target 同 commit 删除）。VoxCore 组包含 §2.1 列出的全部 VoxCore 文件（含 1.6 新建的协议文件与 `ASRProviderType.swift`）；因 1.6 已预置 `import VoxCore`，不改任何 `.swift` 内容也能构建，保证 rename 检测 100% |
| 2.2 | VoxKit | edit commit：拆分为 §2.1 的模块名、import、access level（优先 `package`）、测试 target 对应拆分（`@testable` 18 处随被测类型走）；golden (a)(c) 与 fixture 随之 mv 到 `Packages/VoxKit/Tests/GoldenTraceTests`（`package`/`@testable` 不跨包可见），(b) 与 Bridge 映射留在 VoxPocket；**阶段 2 结束时 `Packages/VoxInfrastructure/Tests/GoldenTraceTests/` 必须为空**（其余探针删除或移到 VoxKitBridge 测试），否则 §9 的树一致性检查失败 |
| 2.3 | VoxKit | `Examples/MinimalConsumer`（macOS + iOS）；「只依赖 VoxSpeech 的产物中无 WhisperKit 模块/符号」检查 |
| 2.4 | VoxInfrastructure | `Sources/TranscriptionKitCombine/` **纯 `git mv`** 到 `Sources/VoxKitBridge/Combine/`（mv commit），随后 edit commit 只改 import 与 manifest（删除 `TranscriptionKitCombine` target）；包装类只用 public async API，因此无需改写。删除 WhisperKit、async-algorithms 依赖（旧 `TranscriptionKit`/`LLMKit` target 已在 2.1 删除以避免模块名冲突）；`PrivateTranscriptionBenchmarkTests` 改依赖 VoxKit products。2.2–2.4 之间 `TranscriptionKitCombine` 的 import 可能暂时失效（E3） |
| 2.5 | VoxApplication | 依赖改为 VoxKit / `VoxKitBridge` |
| 2.6 | VoxPresentation | 同上 |
| 2.7 | App 壳 | import、`project.yml`、`scripts/tests/*.py` 临时包依赖 |
| 2.8 | .github | red lines 扫描范围 = `Packages/VoxKit/Sources` 全部；R4 全量；R2(b)(c) 起覆盖整个 SDK（此前两个 kit 在 VoxInfrastructure 包内，见 §6 R2）；fixture 构建步骤（macOS + iOS Simulator，目的地同 `VOXKIT_IOS_DESTINATION`）；`VoxKitSDK.xctestplan` 与 workspace 改为只引用 `Packages/VoxKit` 与 VoxInfrastructure 的 `VoxKitBridge` 测试 |
| 2.9 | docs | tech-context/frontmatter/AGENTS：VoxInfrastructure 职责去掉「转写 / LLM」，`owns` 去掉 TranscriptionKit/LLMKit、加 VoxKitBridge |

### 4.2 验收

- US1-AC1…AC7（golden 全组相等）；US2-AC1（fixture 以 path 依赖在 macOS 与 iOS Simulator 构建）；US2-AC4（R4 全量）、US2-AC5。
- 合并（merge commit）后在 `main` 上抽查 3 个跨模块迁移文件的 `git log --follow`，能看到阶段 1 之前的提交；结果贴在 PR 评论（US6-AC1 前置）。

### 4.3 风险

| 风险 | 缓解 |
|---|---|
| 跨模块暴露 internal 类型 | 先 mv 后改 access；只把真正跨模块使用的设为 `package`/`public` |
| WhisperKit 仅 product 隔离，仍被解析 | Owner 已定独立 product（§12 Q3）；按 research R-3 如实写入 `ai/COMPATIBILITY.md` |
| 合并方式不是 merge commit 导致历史丢失 | PR-0b + `preserve-history` 标签；合并前 checklist |

### 4.4 PR 边界

PR-2 = 2.1–2.9。不改任何流程逻辑。

## 5. 阶段 3：Workflow 引擎（PR-3，两组 commit）

**一个 PR**（Owner 已定，§12 Q5；属 §1.1 的阶段 PR 例外）：先是 SDK 组（只动 `Packages/VoxKit`），再是 App 组。

### 5.1 SDK 组（只增，不改 App）

| # | 内容 |
|---|---|
| 3.1 | `Definition`：`WorkflowDefinition{version, entry: .speech/.refine, nodes: [NodeSpec]}`、`NodeSpec{id, kind: NodeKindID, inputs: [PortRef], params: JSONValue, onFailure: FailurePolicy}`；Codable；执行前校验（未知 kind、悬空引用、环、端口类型、入口不匹配） |
| 3.2 | `Registry`：`NodeKindID`（`capture.microphone`、`speech.apple`、`speech.azure.batch`、`speech.azure.realtime`、`speech.whisperkit.local`、`merge.llm`、`analyze.intent`、`analyze.tone`、`refine.prompt`、`llm.apple`、`llm.azure`、`output.text`）→ 工厂；宿主可注册自定义节点（日志中记为 `VoxLabel.custom(index:)`） |
| 3.3 | `Scheduler`：拓扑分层；同层 `withThrowingTaskGroup` 并发（节点可声明 `concurrency: 1`）；流式端口用 `AsyncThrowingChannel`，多路 partial 用 `merge`；失败策略 `fail`/`fallback(nodeID)`/`default(JSONValue)`；取消传播 |
| 3.4 | `Events`：`WorkflowEvent`（`partial`、`final`、`level`、`nodeStarted/Finished/Failed(label, reason: VoxLabel)`、`refinedChunk`、`completed`） |
| 3.5 | `DSL`：`@WorkflowBuilder`；`Preset{id, speech, refine}`；`overriding(_:)`，override 键：`speech`、`analysis.<step>`（step ∈ intent/entities/tags/params/tone，逐步覆盖）、`analysis.skip`、`refine.provider` |
| 3.6 | 内置 preset：`hybrid.azure`、`apple.speech`、`hybrid.local` 与 `local.whisperkit`（后两者在 `VoxWorkflowWhisperKit`） |
| 3.7 | 测试：US3-AC1…AC7；SDK 侧 golden (a)(c) 用复制的 fixture；隐私金丝雀跑全部 preset |

### 5.2 App 组（一层一 commit）

| # | 层 | 内容 |
|---|---|---|
| 3.8 | VoxInfrastructure/VoxKitBridge | `StageModelSettings` → `Preset.default.overriding(...)` 映射（EB-1、EB-7、EB-8、EB-9），全组合测试；`WorkflowTranscriptionCoordinator` 转发 `ModelLoadingStartControlling`（保持本地 Whisper「模型未就绪阻止开始录音」，加测试）；`WorkflowTranscriptionCoordinator`（以 `speech` 入口实现 `TranscriptionCoordinator`）；`RefineWorkflowRunner`（`refine` 入口）。**iOS 映射**（今天 App 壳 `#else` 分支，逐条保持，函数名 `IOSPresetMapping`，全组合测试）：(1) speech：batch 配置齐全 → `hybrid.azure` 且 `speech.azure.realtime` 关闭（今天 `realtimeTranscriptionConfig` 在 iOS 恒为 nil）；否则 `apple.speech`，并发出与今天同文的 warning（`Azure transcription configuration missing; actual_provider=appleSpeech`）；(2) refine provider：**初始化时**为 `azureFoundry`（`LLMAppConfig.defaultProvider`），随后若偏好 `llm.provider` 有存值且是合法 `LLMProviderType` → 改为该 provider；**变更通知时**同样只在存值合法时切换，存值未存或非法 → **保持当前 provider**（今天 `applyProviderPreferenceIfExists` 直接 return）；`azureFoundry` 而 Azure 未配置 → 仍选 Azure，节点为「不可用」而非消失（EB-11）；(3) analysis（逐步）：intent 与 tone **固定**为 `appleIntelligence`（`LLMAppConfig.analysisProviderOverrides`），entities/tags/params **跟随当前 refine provider**（今天 `DefaultLLMService` 对无 override 的步骤用默认 provider）；(4) `llm.skipContentAnalysis` → `analysis.skip`；(5) 在 `llmProviderDidChange`/`llmAnalysisSettingsDidChange` 通知时重新应用 (2)–(4)。golden (b) iOS 行（§3.4）在 `App unit tests (iOS)` lane 上与基线比较 |
| 3.9 | VoxApplication | `DefaultRefinementUseCase` 改为只依赖 `RefineWorkflowRunning`（**唯一路径**；不保留 `LLMService` 分支） |
| 3.10 | App 壳（含 `VoxPocketTests`） | 同一 commit：删除 `injectMergerIfNeeded`、transcriber `switch`、`TranscriberProvider`、`DefaultStageTextModelService`、`StageModelRouting.applyTextModels`/`analysisOptions`/`resolveTranscriber`（RB-8、RB-9），每栈独立 `WorkflowRuntime`；iOS `ServiceContainer`（`#else` 分支的 `DefaultLLMService`、`setProvider`、`setSkipContentAnalysis`、偏好通知观察）改接 3.8 的 iOS 映射；`TranscriberSelectionTests`/`RealtimeTranscriberConfigurationTests` 迁为 preset 选择测试（矩阵不缩小）；`scripts/tests/test_realtime_config.py` 同步 |
| 3.11a | VoxInfrastructure | `PrivateTranscriptionBenchmarkTests` 改用 public 的 refine workflow / preset API（今天直接构造 `DefaultLLMService` 并实现 `LLMService`）；该 target 默认跳过，但必须编译 |
| 3.11 | VoxKit | `DefaultLLMService`、`LLMService` 降为 `package`/internal（只供节点使用），R4 与 API 快照更新 |
| 3.12 | docs | tech-context 流程描述；CLAUDE.md「Transcriber Providers」→ preset 表 |

### 5.3 验收

US1 全部（golden 按 §3.4 比较规则，RB-12 放宽；`pipeline` 矩阵含 EB-7 iOS 行，由 `App unit tests (iOS)` 产出）、US3 全部、US4-AC2（全部 preset）；App target 的 macOS 与 iOS build 及 `App unit tests`/`App unit tests (iOS)` 均通过。

### 5.4 风险

| 风险 | 缓解 |
|---|---|
| 分析并发后 FoundationModels 并发会话冲突 | `AppleIntelligenceProvider` 已在内部 `async let` 并发 intent/tone；有问题时 preset 设 `concurrency: 1` |
| 分析结果今天不影响输出（research R-2） | Owner 已定保留 intent/tone 并在阶段 3 同层并行（§12 Q4，RB-12）；golden 仍记录调用 |
| 引擎超出 600 行预算 | 只计 Definition/Registry/Scheduler/Events/DSL；超出在 PR 说明并拆文件，不引第三方引擎 |
| 主/快捷栈共享 runtime 造成污染 | 每栈独立 runtime；US1-AC4 测试 |

### 5.5 PR 边界

PR-3 = 3.1–3.12；SDK 组全部 commit 在 App 组之前。

## 6. SDK 红线的机械检查

脚本 `Packages/VoxKit/scripts/redlines/check.sh`；每条规则有 `fixtures/violations/<rule>/*.swift` 负例和 `fixtures/ok/<rule>/*.swift` 正例，`check.sh --self-test` 证明负例失败、正例通过。**编译型 fixture**（R3(a)、R4(b)）由同一个 harness 函数以同一组参数编译（`swiftc -typecheck -swift-version 6 -I <VoxCore 模块目录> -target <macOS 26 triple>`，模块由同一次 `swift build` 产出）：负例必须以非零退出**且** stderr 匹配 fixture 首行 `// expected-diagnostic: <正则>` 声明的诊断（如 R3(a) 为 `cannot convert value of type 'String' to expected argument type 'StaticString'`），诊断不匹配（例如因模块找不到、语法错误而失败）视为 self-test 失败；每个负例配一个只差违规那一行的正例，正例必须零诊断通过。阶段 1–3 在 VoxPocket `Lint & policy` 执行，阶段 4 后在 VoxKit 的 `quality` lint lane 执行。扫描范围见 §2.2。

| # | 红线 | 检查 |
|---|---|---|
| R1 | 不读 env、不读文件/配置 | 禁止（源码正则）：`ProcessInfo`、`getenv`、`setenv`、`environment\[`、`UserDefaults`、`@AppStorage`、`CFPreferences`、`NSUbiquitousKeyValueStore`、`Bundle\.main`、`Bundle\(for:`、`infoDictionary`、`SecItem`、`Data\(contentsOf:`、`String\(contentsOf`、`contentsOfFile`、`NSDictionary\(contentsOf`、`FileHandle\(forReading`、`InputStream\(`、任意接收者上的 `\.urls?\(for:`、`contents\(atPath:`、`contentsOfDirectory`、`applicationSupportDirectory`、`cachesDirectory`、`documentDirectory`、`homeDirectory`、`NSHomeDirectory`、`NSTemporaryDirectory`、`temporaryDirectory`、`CommandLine`、`environ\b`、`URL\(fileURLWithPath:`。**白名单**：只在新建的 `TemporaryAudioStore.swift`（1.5 的 KI-4 commit 创建；统一负责宿主注入的 `VoxStorageLocations.temporaryAudio` 下 WAV 的建目录/写/读/删，吸收今天分散在 `MicrophoneRecorder` 的 `createDirectory`/`AVAudioFile`、`WhisperEngine.swift` 的 `Data(contentsOf:)`、`AzureWhisperTranscriber`/`HybridWhisperTranscriber`/`HybridLocalWhisperTranscriber` 的 `removeItem`）与 WhisperKit 模型缓存适配器中允许（后者只允许对注入的 `VoxStorageLocations.modelCache` 下路径做 I/O；今天 `WhisperKitTranscriber.huggingFaceWhisperKitRepoCacheCandidates()` 里的 `cachesDirectory`/`homeDirectoryForCurrentUser` 路径解析在 1.5 的 KI-4 commit 中删除，结果改由宿主经 `VoxStorageLocations.modelCacheCleanupCandidates` 注入，App 在 1.10 用同一计算传入，行为不变），且每行需 `// redline-allow: R1 <理由>`（模型缓存适配器的 I/O 只允许作用于 `modelCache` 与 `modelCacheCleanupCandidates` 下的路径；`resetCorruptedCache` 对候选目录的 `removeItem` 因此行为不变）；白名单文件与允许注释数量写死在脚本里，变更属于 CODEOWNERS 覆盖的重要 PR。每个禁止 API 至少一个负例 |
| R2 | 不依赖 LokiKit / shared-telemetry | (a) 源码禁止 `import (LokiKit|SharedTelemetry|\w*Telemetry\w*)`（阶段 1 起覆盖 `Packages/VoxKit` 与两个 kit 的 Sources）；(b) `swift package show-dependencies --format json` 的闭包只允许白名单（`swift-async-algorithms`、`WhisperKit` 及阶段 1 固化的传递依赖快照）；(c) `Package.swift` 禁止 `path:` 指向包外。**(b)(c) 在阶段 2 结束前只作用于 `Packages/VoxKit`**：两个 kit 仍在 VoxInfrastructure 包内，该包合法依赖 LokiKit 与 `../VoxDomain`，此期间 kit 的依赖由 (a) 与 1.5 删除 `CoreModels`/LokiKit target 依赖保证；2.8 起 (b)(c) 覆盖整个 SDK |
| R3 | 日志/遥测无转写、音频、精炼文本 | (a) 类型化：`VoxLogger.log` 只收 `StaticString` 消息与 `VoxLogField`（键为 `StaticString`，值只有 Int/时长/Bool/`VoxLabel`），`VoxTelemetryEvent` 同理——传入 `String` 无法编译（负例 fixture 以「必须编译失败」验证）；(b) 静态：禁止 `print(`、`debugPrint(`、`dump(`、`NSLog`、`os_log`、`import OSLog`、`Logger\(subsystem`；(c) 动态：隐私金丝雀测试，所有入口/preset 用含金丝雀串的假数据运行，日志、遥测、`VoxKitError.errorDescription` 与 `localizedDescription` 中不得出现金丝雀串 |
| R4 | async/await + `AsyncThrowingStream` 公共 API | (a) 源码禁止 `import Combine`；(b) 构建时 `-emit-symbol-graph`，脚本解析 public/open 符号：拒绝类型名含 `Publisher`/`Subject`/`Cancellable`；拒绝**任何** public/open 符号（参数、属性、下标、返回值）的声明片段中出现函数类型——不论是否 `@escaping`、是否 Optional（Optional 闭包隐式逃逸）；允许清单写死在脚本里（`NodeRegistry.register(_:factory:)`、`@WorkflowBuilder` 相关、`AsyncThrowingStream` 构造相关）；负例覆盖 `completion:`、`onResult:`、`callback:`、Optional completion 参数（`((Result) -> Void)? = nil`）、public 闭包属性（`var onEvent: ((X) -> Void)?`） |
| R5 | 无产品/供应商标识 | 对 `Sources/`、`Tests/`、`Examples/`：禁止 `VoxPocket`、`com\.leepepe`、`[a-z0-9-]+\.services\.ai\.azure\.com`、`[a-z0-9-]+\.openai\.azure\.com`、`[a-z0-9-]+\.cognitiveservices\.azure\.com` 中非 `example` 的主机、GUID 形式的租户/订阅 ID |

并发（宪法 III 修订后）：`@unchecked Sendable`/`nonisolated(unsafe)` 每处须有 `// Sendable:` 理由注释，且理由属于修订后允许的类别（Combine 桥接〔仅 App 侧 `VoxKitBridge`〕、AVFoundation/Speech/WhisperKit 回调桥接）；SDK 内计数只能下降，基线在 1.2 记录（US4-AC4）。

## 7. iOS 启用路径

| 步 | 何时 | 内容 | 验收 |
|---|---|---|---|
| I-1 | S3（PR-1 等 S3 合并，Q8；PR-1 只核对） | AGENTS / constitution / CLAUDE 删除「暂停 iOS」表述；保留「iOS TestFlight 需另行授权」 | US5-AC3 |
| I-2 | PR-1 1.7 | iOS 采集完善（RB-11） | US5-AC2 |
| I-3 | PR-1 1.11 | `iOS SDK` lane（`VoxKitSDK.xcworkspace`/scheme `VoxKitSDK`/`VoxKitSDK.xctestplan`，目的地 `VOXKIT_IOS_DESTINATION`）覆盖 `Packages/VoxKit` 与 VoxInfrastructure 的 kit/Combine/Bridge/golden test targets；`App unit tests (iOS)` 覆盖 `VoxPocketTests`（非 required） | — |
| I-4 | PR-1 合并后 | lane 绿 → Owner 批准 → ruleset apply（1.12） | US5-AC1 |
| I-5 | PR-2/3 | 每个 PR 跑 `iOS SDK` 与 `App unit tests (iOS)`；App `App target` 的 iOS build 保持 | — |
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
| Additional Constraints | 「LokiKit is external」旁增「VoxKit：阶段 1–3 为本仓暂存包 `Packages/VoxKit`，阶段 4 起为远程 exact 版本依赖」；增「非公开项目配置（Azure 主机名、内部 endpoint/配置、内部 issue 号）不进 git：用 gitignore 的本地文件，仓内只提交 `.example` 模板（`config.private.json`/`config.example.json` 模式）」（Owner Q2） | Owner Q2 | 阶段 4 再改一次；PR-0c |
| Quality Gates | 增：SDK red lines（R1–R5）、VoxKit iOS Simulator 测试与 App iOS Simulator 单元测试属于 CI required | — | ruleset 经 Owner 批准 |
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
     --path Packages/VoxInfrastructure/Tests/GoldenTraceTests/ \
     --path LICENSE \
     --path-rename Packages/VoxKit/: \
     --path-rename Packages/VoxInfrastructure/Sources/TranscriptionKit/:Sources/VoxSpeech/ \
     --path-rename Packages/VoxInfrastructure/Sources/LLMKit/:Sources/VoxLLM/ \
     --path-rename Packages/VoxInfrastructure/Tests/TranscriptionKitTests/:Tests/VoxSpeechTests/ \
     --path-rename Packages/VoxInfrastructure/Tests/LLMKitTests/:Tests/VoxLLMTests/ \
     --path-rename Packages/VoxInfrastructure/Tests/GoldenTraceTests/:Tests/GoldenTraceTests/ \
     --mailmap ../export-rules/mailmap.txt \
     --replace-text ../export-rules/replace-text.txt \
     --replace-message ../export-rules/replace-message.txt
   ```
   - **规则文件（Owner Q2）**：放在临时目录 `export-rules/`（与 clone 平级），**不提交**；只含通用正则，不写任何具体主机名或个人邮箱：
     - `mailmap.txt`：导出历史中出现的**每个**作者/提交者身份（由 `git log --format='%an <%ae>%n%cn <%ce>' | sort -u` 生成，只在本机临时文件中）映射为 `LeePepe <13819054+LeePepe@users.noreply.github.com>`；个人邮箱从导出历史中删除。
     - `replace-text.txt`（blob 内容）：`regex:[a-z0-9-]+\.services\.ai\.azure\.com==>example.services.ai.azure.com`、`regex:[a-z0-9-]+\.openai\.azure\.com==>example.openai.azure.com`、`regex:[a-z0-9-]+\.cognitiveservices\.azure\.com==>example.cognitiveservices.azure.com`（`example` 主机保持不变）、`regex:\bMY-[0-9]+\b==>internal-issue`、GUID 形式的租户/订阅 ID → 全零 GUID。
     - `replace-message.txt`（提交信息）：`(#NN)` → `(LeePepe/VoxPocket#NN)`；`\bMY-[0-9]+\b` → `internal-issue`；trailer（`Co-Authored-By`/`Signed-off-by`）中除 `users.noreply.github.com` 与 `noreply@anthropic.com` 外的邮箱 → `13819054+LeePepe@users.noreply.github.com`。
   - `Tests/GoldenTraceTests/` 的旧路径 rename：阶段 1 的 golden (a)(c) 在 `Packages/VoxInfrastructure/Tests/GoldenTraceTests/`，阶段 2 迁到 `Packages/VoxKit/Tests/GoldenTraceTests/`；加入 `--path` 才能保留其阶段 1 历史。前提是阶段 2 结束时旧目录为空（2.2），否则树一致性检查失败。
   - 旧路径 rename 只让迁移前历史落在合理位置；`TranscriptionKitCombine`（1.6 起的独立 target，2.4 迁到 `VoxKitBridge`）不在导出范围内，其 1.6 之前在 kit 路径下的历史会被带出，属预期。
   - 树一致性：`git fetch <VoxPocket-url> main:orig-main` 后 `git diff --stat HEAD^{tree} orig-main:Packages/VoxKit -- . ':!LICENSE'` 必须为空（`--replace-text` 在 `main` 上不应改动任何文件，因为 PR-0c/RB-6 已使当前树零命中；若不为空，说明树上仍有非公开信息，停下交 Owner）。
   - `--no-tags` 且推送前 `git tag -l` 为空（不带 `testflight/*` 等 tag）。
2. **隐私预检**（发现即停，交 Owner）：
   - `gitleaks detect --log-opts="--all"` 全历史；
   - 全历史 blob 与提交信息 grep：shared-ci `forbidden_patterns`（身份/本机路径）、`config.private.json` 与 `*.private.*`、`.services.ai.azure.com`/`.openai.azure.com`/`.cognitiveservices.azure.com` 非 `example` 主机、GUID、`MY-[0-9]+` 等内部 issue 号、`com.leepepe`；
   - 列出历史中所有二进制与音频 blob（`*.wav`、`*.m4a`、`*.caf`、`*.mp3`），应为零；
   - `git log --format='%an <%ae>%n%cn <%ce>' | sort -u` 列出作者/提交者；
   - 输出只含计数与 commit SHA 的报告（不贴内容）交 Owner。
   - 已知命中（Owner 个人邮箱、提交信息中的内部 issue 号、测试历史中的 Azure 资源主机名）已由上面的 `--mailmap`/`--replace-message`/`--replace-text` 处置（Owner Q2）；预检在处置后的导出历史上重跑，必须零发现，否则停下交 Owner。
3. **建 repo 并推送**：Owner 确认后建 `LeePepe/VoxKit`（public，MIT），推 `main`。
4. **`repo-kit init`（VK-1 PR）**：按 shared-ci@<当时发布的 40 位 SHA> 模板：AGENTS.md（≤150 行；Read first / Protocol / Verify / Required checks / Red lines / Delivery / Dependencies）、thin CLAUDE.md、`scripts/verify`（macOS `swift build/test`、iOS Simulator `xcodebuild test`（目的地同 `VOXKIT_IOS_DESTINATION`）、`scripts/redlines/check.sh` + self-test）、`.githooks/pre-push`、caller `ci.yml`（`runs-on: macos-26`；build/test 输入含 iOS Simulator，计入 `quality / aggregate`；contract audit；workflow-lint；PR body 检查）、`review.yml` caller、PR 模板、CODEOWNERS（`/.github/`、`/AGENTS.md`、`/Package.swift`、`/scripts/redlines/`、`/ai/`、`/.gitignore`）、根 `tech-context.md` layer 表（每个 module 一个 layer）；`ai/` 七件套（README/USAGE/INTEGRATION/EXAMPLES/COMPATIBILITY/MIGRATION/registry.json）。**非公开配置（Owner Q2）**：`.gitignore` 忽略 `*.private.*`、`*.local.*`、`config.private.json`；需要真实 endpoint 的只有可选（默认跳过）的集成测试，它们由测试 harness 读取 gitignore 的 `Tests/Integration/azure.local.json`，仓内提交 `Tests/Integration/azure.example.json`（只含 `example` 主机与空 key）；AGENTS「Red lines」写明该规则；`scripts/verify` 与 CI 运行 gitleaks 与 R5 模式扫描，命中即失败。验收：shared-ci `audit` 零发现。
5. **ruleset**：old→new 给 Owner，批准后设置：禁直推；required `quality / aggregate` 与 `codex-review-target / codex-review`；**tag 保护**（Owner Q6）：tag ruleset 作用于 `refs/tags/*`，规则 `creation`、`update`、`deletion`、`non_fast_forward` 全部启用，bypass actor 只有 repository admin（Owner），即只有 Owner 能创建 tag、任何人不能移动或删除；若日后用 release workflow 建 tag，须把该 workflow 的 App 另列为 `creation` 的 bypass actor，并经 Owner 批准；回读 `rules/branches/main` 与 tag ruleset。
6. **Tag**：`0.1.0`（Owner 已定，§12 Q6；由 Owner 或其批准的发布流程在 tag 保护生效后创建），release notes 指向 `ai/`；按 W5 用 `ai/INTEGRATION.md` 的外部消费者 fixture 在干净目录以 `exact: "0.1.0"` 在 macOS 与 iOS Simulator 构建。
7. **VoxPocket `repo-kit adopt`（PR-4）**：
   - 4.1（E2）：VoxInfrastructure/Application/Presentation 的 `Package.swift` 与 `project.yml` 同一 commit 改为 `.package(url: "https://github.com/LeePepe/VoxKit", exact: "0.1.0")`，删除 `Packages/VoxKit`。
   - 4.2：`.gitignore` 只放行 `Packages/VoxInfrastructure/Package.resolved`、`Packages/VoxApplication/Package.resolved`、`Packages/VoxPresentation/Package.resolved` 与 `VoxPocket/VoxPocket.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`，并提交这 4 个文件（合同第 7 项比对依据）。
   - 4.3：CI 删除 `SPM VoxKit`、`iOS SDK` 中的 VoxKit 部分（改由 VoxKit repo required 保证）与 `VoxKitSDK.xcworkspace`/scheme/test plan（改为只含 `VoxKitBridge` 测试或删除），`Lint & policy` 删 SDK red lines 步骤；`App unit tests (iOS)` 保留；ruleset 映射 old→new 经 Owner 批准，合并后 apply。
   - 4.4：`check_frontmatter.py` 视 VoxKit 为外部；宪法 Additional Constraints、tech-context、AGENTS「Dependencies」段（`VoxKit 0.1.0` + `…/0.1.0/ai/` 链接）；本地切 path 依赖的方法（`swift package edit` / Xcode 本地覆盖）写入 AGENTS，**不得提交**。
   - App 侧 golden (b) 与 Bridge 映射测试、全部既有测试通过。
8. **回滚演练**：从 PR-4 开 revert 草稿分支跑 CI，绿后关闭（US6-AC6）。

## 10. PR / 阶段总览

| PR | 阶段 | 仓 | 依赖 | Owner 批准点 |
|---|---|---|---|---|
| PR-0（本 PR） | spec/plan | VoxPocket | — | spec、plan、§12 问题 |
| PR-0b | policy | VoxPocket | PR-0 | `auto-merge.yml` 的 `preserve-history` 例外（Q9 已批准，PR 上确认实现） |
| PR-0c | hygiene | VoxPocket | PR-0 | 非公开信息清理（Owner Q2）：一层一 commit 删除当前树中的内部 issue 号（今天 3 个文件：App 测试注释、`scripts/ci` 注释、基准测试 README）与 `.claude/plan/` 旧计划文档中的真实 Azure 资源主机名（`*.cognitiveservices.azure.com` 形式，换 `example`）；完成标准为仓库级 `git grep -E` 对 `MY-[0-9]+` 与三种 Azure 主机形式（非 `example`）零命中（`AzureFoundryProviderRequestTests` 由 RB-6 在 PR-1 处理，列为已知例外）；VoxPocket 自身历史不改写（Q2 只要求导出历史），如需改写另行请 Owner 决定；AGENTS/宪法写入「gitignore 本地文件 + `.example` 模板」规则（与 §8 同步可并入 1.1）；`.gitignore` 增加 `*.local.*`。只改树，不改 VoxPocket 历史 |
| PR-1 | 1 接缝 | VoxPocket | PR-0b、PR-0c、S3（Q8）/S5 | 修宪 1.2.0、RB-1…RB-7、RB-11、ruleset |
| PR-2 | 2 搬迁 | VoxPocket | PR-1 + ruleset apply | 依赖变更、E1 |
| PR-3 | 3 引擎 + 替换 | VoxPocket | PR-2 | RB-8、RB-9、RB-12 |
| VK-1 | 4 init | VoxKit | PR-3 + 隐私预检 | 预检结果、ruleset 与 tag 保护、tag |
| PR-4 | 4 adopt | VoxPocket | VK-1 tag | 依赖 pin、E2、ruleset 映射 |

## 11. Plan-Review Loop 记录

| 轮 | 结论 | 发现 | 处理 |
|---|---|---|---|
| 1 | NEEDS_REVISION | 4 CRITICAL、12 MEDIUM、10 LOW | 见下 |
| 2 | NEEDS_REVISION | 0 CRITICAL、6 MEDIUM（C2 在文件映射层面回归 + 5 个新问题）、8 LOW；确认 C1、C3、C4、M1–M12 已解决 | 见下 |
| 3（上限） | NEEDS_REVISION | 0 CRITICAL、3 MEDIUM（N1–N3）、3 LOW；确认 M-B、M-C、M-D 已解决，M-A/M-E/M-F 规则正确但与现有代码存在未映射的违规 | 已按下列修订；修订后未再经 reviewer 复核，按 Q10 交独立复核 |
| 3b（独立复核 @557f139） | NEEDS_REVISION | 0 CRITICAL、6 MEDIUM（(a)–(f)）、4 LOW | 已按下列修订，并编码 Owner Q1–Q10 决定 |
| 4（Q10 的一轮独立复核，本修订） | NEEDS_REVISION | 0 CRITICAL、6 MEDIUM（R4-M1…M6）、10 LOW；确认 Q1–Q10 已完整编码，(a)(d)(e)(f) 与上轮 LOW 已解决，(b)(c) 部分解决 | 第 4b 轮修订 MEDIUM 全部与多数 LOW，见下 |
| 4b（修订，未再复核） | — | — | 按 Q10 不再循环复核，交 Owner 审阅为最终结论 |

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

第 3b 轮（独立复核，@557f139）要点与修订：
- (a) 阶段 1 成环：`ModelLoadingStateProviding`/`SpeechSession`/`TranscriptionEvent` 原计划阶段 1 进 VoxCore，却依赖阶段 2 才移动的 `ModelLoadingState`/`TranscriptionResult` → 阶段 1 在 TranscriptionKit 新建无 Combine 文件声明，`module-map.json` 映射到 VoxCore，2.1 mv；VoxCore 阶段 1 只含不引用 kit 类型的类型（§2.1、§2.4）。
- (b) Combine 适配器无法以 extension 形式跨 target 访问 `private` subject → 1.6 起改为独立 target `TranscriptionKitCombine` 中的包装类，只用 public async API；`wrap(_:)` 保持运行时 conformance 表；2.4 为纯 mv（§2.2）。
- (c) 缺 iOS 映射 → 3.8 增加 iOS speech（batch 有→Hybrid 无 realtime，否则 Apple Speech + 同文 warning）、固定 intent/tone Apple、未存偏好→`azureFoundry`；golden (b) iOS 行改由 `App unit tests (iOS)` lane 产出（§3.4、1.11）。
- (d) 删除缓存路径解析会丢失 HuggingFace 缓存清理 → `VoxStorageLocations.modelCacheCleanupCandidates`，App 用今天同一计算传入（§2.4、1.5、1.10、R1）。
- (e) golden (c) 无授权接缝无法在 CI 运行 → §3.1a 定义授权提供者与录音源/识别器/批量/realtime 协议；1.0b 的 CI run 是 1.5 之前的闸门。
- (f) R3(a)「必须编译失败」可能因错误原因通过 → self-test 匹配期望诊断文本，正例由同一 harness 同一参数编译（§6）。
- LOW：R2(b)(c) 阶段 2 结束前只作用于 `Packages/VoxKit`；`iOS SDK` 的 workspace/scheme/test plan 与固定 Simulator 目的地；`ModelLoadingStartControlling` 归 VoxCore；filter-repo 增加 `GoldenTraceTests` 路径。
- Owner 决定：§12 全部标为已决；Q2 改写导出命令（`--mailmap`、`--replace-text`、`--replace-message`）、新增 PR-0c 与 VK-1 的 gitignore + `.example` 步骤；Q8 删除 PR-1 自带 S3 改动的回退；Q6 增加 tag 保护；Q5 记为阶段 PR 例外。

第 4 轮（Q10 独立复核）要点与第 4b 轮修订（未再复核）：
- R4-M1 包装类无法从 async API 重建今天的 Combine 面（`supportedLanguages`、`providerType`、分开的麦克风/语音权限、会话前订阅的状态/电平、`isTranscribing`、同步 pause/resume），且 `ASRProviderType` 随协议文件进 Combine target 会让核心类失去它 → `SpeechSessionSource` 补齐能力面（§2.4），`ASRProviderType` 拆出进 VoxCore，包装类用串行队列转 pause/resume，golden (c) 增加 pause/resume 与会话前订阅用例。
- R4-M2 2.1 纯 mv commit 缺 `import VoxCore`、VoxSpeech 与 VoxSpeechWhisperKit 分开 mv 会出现两个 `TranscriptionKit` 模块 → 1.6 预置 `import VoxCore` 并由 `module-map.py` 检查；2.1 按依赖序且同源模块同 commit。
- R4-M3 iOS 分析路由今天 entities/tags/params 落到 refine provider（macOS 跟随 intent），只按 intent/tone 建模会漏掉 iOS 的 Azure 分析调用 → override 键与 `pipeline.analysis` 改为逐步五项，3.8 与 spec EB-7 写明规则。
- R4-M4 1.0a 的 `AsyncStream` 电平接缝会改变多订阅者时序 → 1.0a 保留 Combine publisher，1.6 再改。
- R4-M5 golden (b) iOS 行没有在未改代码上的基线 → 新增 1.0c（App 壳 `GoldenRoutingTests` + 提前加入 `App unit tests (iOS)` lane），闸门覆盖 (b) iOS 行与 (c)，T102a。
- R4-M6 隐私模式漏 `*.cognitiveservices.azure.com`，树上 `.claude/plan/` 有真实主机 → R5、`replace-text`、预检、PR-0c/T004（仓库级 `git grep`）均加入该形式。
- LOW 已修：iOS 非法/删除偏好保持当前 provider；逐协议 conformance（`WhisperKitTranscriber` 无 `ModelLoadingStartControlling`）；定义 `MergerConfigurable`；`TranscriptionKitCombine`/`VoxKitBridge` library product；例外 E4（1.0b/1.0c/1.10/1.11 连带 harness/仓根）；`module-map.py` 位置；tag ruleset 含 `creation`；`iOS SDK` lane checkout LokiKit；`authorizationStatus()` 进授权接缝；Combine 形状 kit 测试改写列入 PR 说明；关键路径含 T003。
- LOW 未采纳：noreply 地址仍写在 plan 中（Owner 在 Q2 中明确指定，且为公开 noreply 地址）。

## 12. Owner 决策（已定，2026-09-24）

Q1–Q10 均已由 Owner 决定（来源：Owner 的仓库治理计划 §18，未入库；以本表为准）。

| # | 问题 | 决定 | 落实位置 |
|---|---|---|---|
| Q1 | 各阶段 PR 由谁执行 | **已定**：阶段 1 起交 Dev Team；Multica 不可达期间由 subagent 执行 | 文首「执行方」；tasks T003 |
| Q2 | 导出历史中的个人信息与非公开项目信息（**Owner 修改了选项**） | **已定**：(1) 个人信息（作者/提交者邮箱、trailer 中的个人邮箱等）从导出历史中**删除**：filter-repo 用 `--mailmap` 统一改为 `13819054+LeePepe@users.noreply.github.com`；(2) 非公开项目信息（Azure 主机名、内部 endpoint/配置、`MY-` 内部 issue 号）**不进 git**：导出历史用 `--replace-text`（blob）与 `--replace-message`（提交信息）替换；当前树由 PR-0c 与 RB-6 清理；(3) VoxPocket 与 VoxKit 都采用 `config.private.json` 模式：真实值放 gitignore 的本地文件，仓内只提交 `.example` 模板；VK-1 增加 gitignore + example 步骤 | §8 Additional Constraints；§9 步骤 1、2、4；§10 PR-0c；tasks T00x、T401、T404 |
| Q3 | WhisperKit 隔离级别 | **已定**：独立 product（`VoxSpeechWhisperKit`），不拆第二个包；SPM 仍解析 WhisperKit，如实写入 `ai/COMPATIBILITY.md` | §2.1；§4.3；US2-AC5 |
| Q4 | 意图/语气分析今天不影响精炼输出 | **已定**：保留 intent/tone，阶段 3 同层并行（RB-12 的排序放宽） | §3.4 比较规则；§5.4；RB-12 |
| Q5 | 阶段 3 是否拆 PR | **已定**：一个 PR（SDK 组在前，App 组在后）。阶段 PR 跨多层是 Owner 批准的「一层一 PR」例外，commit 仍一层一个 | §1.1；§5 |
| Q6 | 首个 tag | **已定**：`0.1.0`；`LeePepe/VoxKit` 设 tag 保护。另：App 与 VoxKit 都需要 iOS build/test（App 单元测试也跑 iOS Simulator） | §9 步骤 5、6；1.11 `App unit tests (iOS)` |
| Q7 | RB-2 删除 `LocalWhisperRawOutputLogger` 及其测试 | **已定**：删除 `LocalWhisperRawOutputLoggerTests`，新增「日志不含转写」测试（金丝雀转写经 WhisperKit 路径后，日志与遥测中不出现） | 1.5；spec RB-2；tasks T108 |
| Q8 | S3 未合并时 PR-1 怎么办 | **已定**：PR-1 等 S3 合并；PR-1 不自带 S3 的 lane 与「iOS 暂停」表述修改（原回退方案已删除） | 文首前置；§3.1 1.11 注；§7 I-1；§10 |
| Q9 | 阶段 PR 用 merge commit 保留历史 | **已定**：同意 `preserve-history` 标签例外与 merge commit（PR-0b） | §1.2；§10 PR-0b；RB-13 |
| Q10 | 本 plan 的放行条件 | **已定**：本修订后做**一轮**独立复核（§11 第 4 轮），之后以 Owner 审阅为最终结论 | §11 |
