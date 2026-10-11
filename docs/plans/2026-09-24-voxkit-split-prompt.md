# 任务：VoxPocket 拆分为 VoxKit（语音 SDK，独立 repo）+ VoxPocket（UI App）

## 0. 前置：去掉 Linear

- 已在分支 `docs/drop-linear-workflow`（commit `c3b283d`）删除 `CLAUDE.md` 中 TIA-6 链接与 "Task Workflow" 的 Linear 步骤（建 issue / 子 issue / API ID）。
- 若尚未合并：push 该分支并开 PR 到 `main`，等 required checks 通过后自动合并。
- 之后任务流程不再使用 Linear：planner 拆解 → 计划记录到 spec-kit（`specs/`）或 `docs/plans/` → Plan-Review Loop 直至 APPROVED → 独立子任务并行分派。

## 1. 目标

把语音能力抽成独立 SwiftPM SDK「VoxKit」，提供：

- 接入不同 SR：Apple Speech / Azure Whisper batch / Azure Realtime / 本地 WhisperKit / Hybrid 双路
- 接入不同 LLM：Apple Intelligence / Azure Foundry，可扩展
- 不同 refine 策略：RefinementType、prompt 构建、intent/tone 分析、双路转写合并
- 可组合的 workflow，面向不同项目/人群定制，支持三种方式：
  1. **代码写死**：Swift result builder DSL
  2. **UI 编辑**：Codable JSON 定义，节点以 registry id 引用（如 `speech.azure.realtime`、`llm.apple`）
  3. **Toggle**：preset + overrides；现有 `StageModelSettings` 即等价于 `Preset.default.overriding(...)`

  三者都编译为同一个 `WorkflowDefinition`。

当前 App（VoxPocket）只保留 UI、编辑器领域、持久化、平台适配，通过 VoxKit 使用语音能力。

## 2. 现状要点

动手前先读：`AGENTS.md`、`.specify/memory/constitution.md`、`docs/architecture/tech-context.md`、相关 `Packages/<pkg>/tech-context.md`。

- 迁出候选：`Packages/VoxInfrastructure/Sources/TranscriptionKit`、`LLMKit`（约 5.3k 行）
- 耦合点：
  - TranscriptionKit / LLMKit / PlatformAdapters 直接依赖 LokiKit
  - 凭据来自 env + `config.private.json`；阶段→模型路由在 App 壳 `LLMAppConfig`、`StageModelRouting`
  - 流程写死：`DefaultLLMService.analyzeContent`、`HybridWhisperTranscriber`、`ServiceContainer.injectMergerIfNeeded`
  - API 风格混用：转写用 Combine publisher，LLM 用 `AsyncThrowingStream`

## 3. VoxKit 目标结构

| Module | 内容 |
|---|---|
| VoxCore | 错误、`TranscriptionResult`、`VoxLogger`/`VoxTelemetry` 协议、`CredentialProvider` 协议 |
| VoxSpeech | AppleSpeech / AzureWhisper / AzureRealtime / Hybrid 适配器（含麦克风采集，待确认） |
| VoxSpeechWhisperKit | 本地 WhisperKit，独立 product，避免强制引入重依赖 |
| VoxLLM | LLMProvider：AppleIntelligence / AzureFoundry |
| VoxRefine | refine 类型、PromptBuilder、intent/tone 分析、TranscriptionMerger |
| VoxWorkflow | 轻量 DAG 引擎 + 定义格式 + 内置 presets |

App 侧保留：

- **VoxDomain**：Session / Patch / TextHistory
- **VoxInfrastructure**：仅 Persistence / PlatformAdapters / Preferences + LokiKit 适配器
- **VoxApplication**：Editing / Session / History；Recording / Refinement 改为调用 VoxKit workflow
- **VoxPresentation**：另加 workflow 设置 UI

## 4. SDK 边界红线

- SDK 不读 env、不读文件；凭据由宿主通过 `CredentialProvider` 注入，私密配置加载留在 App（宪法 V 继续约束 App）
- SDK 不依赖 LokiKit，只暴露日志/遥测协议，由 App 用 LokiKit 实现
- 转写内容、音频、refine 文本不得进入日志/遥测（宪法 IV 作为 SDK 自身红线）
- 对外 API 统一 async/await + `AsyncThrowingStream`；需要 Combine 时由 App 侧薄桥接
- 遵守 `Mutex<State>`、`@MainActor`、`Sendable` 等并发约束

## 5. Workflow 引擎选型

- 先调研现成 Swift 库并联网核实。初步判断：Square `workflow-swift` 面向 UI 状态机；Temporal 太重且需 server；LangChain 类 Swift 移植不成熟。
- 默认方案：基于 Swift Concurrency + `swift-async-algorithms` 自研，预计 400–600 行。
- 默认流程：`capture → transcribe → [merge] → analyze(intent ∥ tone) → refine → output`

## 6. 分阶段迁移

每阶段可独立 build/test/合并，一层一 commit，走 PR。

1. **仓库内切接缝**：新建 `Packages/VoxKit` 暂存包；LokiKit 改为协议注入；env 读取移出库；API 统一为 async
2. **搬迁**：TranscriptionKit / LLMKit 移入 VoxKit，App 改为依赖它，行为不变，用现有测试兜底
3. **Workflow 引擎**：先实现复刻现有行为的内置 preset + golden test，再替换 `ServiceContainer` 中写死的逻辑
4. **拆 repo**：`git filter-repo` 保留历史 → 新 repo 打版本 tag → App 改为远程 SPM 依赖（本地开发可切回 path 依赖）
5. **（可选）** 设置页 workflow 编辑 UI

## 7. 风险

- 新 repo 需另配 CI、门禁、required checks、tech-context/frontmatter 防腐
- 宪法依赖方向图与各层 tech-context 需同步修订（按 Governance 流程修宪）
- iOS 从未编译通过（移植债）；当前仅推进 macOS

## 8. 待决策（开始前向用户确认）

1. SDK 名称（暂定 VoxKit），GitHub 公开还是私有
2. 麦克风采集是否放进 SDK（倾向放）
3. 平台范围：仅保证 macOS，还是 iOS 也要能编译
4. 拆 repo 时机：先在仓库内完成阶段 1–3 再拆（推荐），还是一开始就建新 repo

## 执行要求

- 先按 `CLAUDE.md` 的 Plan-Review Loop 出详细计划（每阶段的子任务、验收标准、风险），review 通过（APPROVED）后再交给用户批准执行
- 不跨层混改；遵守 PR → main 流程，不用 `--no-verify`
