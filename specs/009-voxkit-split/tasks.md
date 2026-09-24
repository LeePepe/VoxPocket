# VoxKit 拆分任务（依赖顺序）

格式：`T<阶段><序号>`（下游层在同一 PR 内可暂时编译失败，见 plan §1.1 例外 E3；PR head 必须全绿） · `[P]` = 同一 PR 内可与相邻 `[P]` 并行（不同层、无共享文件）· 依赖列未写 = 依赖上一行 · 每个任务 = 一个或多个同层 commit（「层」见 plan §1）；`GATE` 行不是 commit，是合并前必须满足的检查。AC 见 spec §4。

## 阶段 0：前置

| ID | 任务 | 依赖 | 完成标准 |
|---|---|---|---|
| T001 | Owner 批准本 spec/plan 并回答 plan §12 Q1–Q10 | 本 PR | PR 上有批准与答复 |
| T002 | PR-0b：`auto-merge.yml` 对 `preserve-history` 标签不挂 squash（RB-13，若 Q9=a） | T001 | 合并；测试 PR 验证带标签时不挂 auto-merge |
| T003 | 确认 S3、S5 状态；按 Q8 处理 | T001 | 状态记录在 PR-1 描述 |

## 阶段 1：仓内切接缝（PR-1）

| ID | 层 | 任务 | 依赖 | AC |
|---|---|---|---|---|
| T101 | VoxInfrastructure | 注入接缝（零行为变化）：Hybrid/Apple transcriber 的 internal init | T002, T003 | US1-AC1 |
| T102 | VoxInfrastructure/Tests + scripts | golden 基线 (a)(b)(c)，`golden-trace/v1` schema，`scripts/tests/test_golden_routing.py` | T101 | US1-AC1 |
| T103 | docs/.specify + scripts/gates | 修宪 1.2.0；`Packages/VoxKit/tech-context.md`；根 tech-context / AGENTS / dependency-graph；`check_frontmatter.py` 识别 VoxKit | T102 | US7-AC1, US7-AC2 |
| T104 | VoxKit | 新包 VoxCore + VoxCoreTests | T103 | US2-AC2/AC3/AC6 |
| T105 | VoxKit | `scripts/redlines` R1–R5 + 负例 + `--self-test`；记录 Sendable 基线；对当前 kit 代码跑一次，产出违规基线清单，逐项映射到 T107–T111 | T104 | US4-AC1, US4-AC3, US4-AC4 |
| T106 | VoxKit | 金丝雀测试工具 | T104 | US4-AC2 |
| T107 | VoxInfrastructure | LokiKit → VoxCore、`StaticString` 日志（RB-4）、按文件多 commit | T105, T106 | US2-AC3, US1-AC5 |
| T108 | VoxInfrastructure | RB-1、RB-2（按 Q7）、RB-3（同时更新基线）、RB-5、RB-6，各一 commit | T107 | US4-AC2, US1-AC5, US1-AC6 |
| T108a | VoxInfrastructure | `GuidedGenerationTests` 改为 `XCTSkip` + test plan 开关，移除内容 `print` | T108 | US4-AC2 |
| T109 | VoxInfrastructure | 新建 `TemporaryAudioStore` 统一临时音频 I/O；注入 `VoxStorageLocations`（KI-4）；删 `CoreModels` 依赖与无用 `import Combine` | T108 | US2-AC6 |
| T110 | VoxInfrastructure | 拆混合文件（`MultiRecognizerTranscriber`、`AudioCaptureState`、`ModelLoadingStartControlling`）+ `module-map.json` 与检查；四个 Combine 协议文件整体进 `Combine/`；新增 `ModelLoadingStateProviding`、`SpeechSessionFactory`；`MicrophoneRecorder.start` 改为 `AsyncStream`；async 核心 + `Combine/` 子目录适配（RB-7）；新 target `VoxKitBridge` | T108a, T109 | US2-AC4, US1-AC1 |
| T111 | VoxInfrastructure | iOS 采集（RB-11）+ 合成音频源 | T110 | US5-AC2 |
| T112 [P] | VoxApplication | import / 错误匹配 | T110 | US1-AC2 |
| T113 [P] | VoxPresentation | import | T110 | US1-AC2 |
| T114 | App 壳 + scripts/tests | `ServiceContainer`/`LLMAppConfig` 注入；`allowedMessages`；`test_realtime_config.py` 依赖 | T111–T113 | US1-AC1/AC5/AC7 |
| T115 | .github | 非 required lane：`SPM VoxKit`、`iOS SDK`、`App unit tests`；`SDK red lines` 步骤 | T114 | US4-AC3, US5-AC1 |
| T116 | scripts/rulesets | `main-protection.json` 加入新 check（只改文件） | T115 | US5-AC1 |
| GATE-1 | — | 违规基线清单清零；golden 全组相等；全部 required 绿；三个新 lane（`SPM VoxKit`、`iOS SDK`、`App unit tests`）全绿 | T116 | US1-AC1 |
| T117 | 线上 | PR-1 以 merge commit 合并后，Owner 批准 → `scripts/rulesets/apply` → 回读 | GATE-1 | US5-AC1 |

## 阶段 2：搬迁（PR-2）

| ID | 层 | 任务 | 依赖 | AC |
|---|---|---|---|---|
| T201 | VoxKit + VoxInfrastructure/Package.swift（E1） | 按模块分组的纯 `git mv` + 最小 manifest（过渡 target 名） | T117 | US6-AC1 |
| T202 | VoxKit | 拆为 plan §2.1 模块、import、access level、测试 target；golden (a)(c) 迁入 VoxKit tests | T201 | US2-AC5 |
| T203 | VoxKit | `Examples/MinimalConsumer`（macOS + iOS）+ 无 WhisperKit 符号检查 | T202 | US2-AC1, US2-AC5 |
| T204 | VoxInfrastructure | `Combine/` 适配 mv 入 `VoxKitBridge`（mv + edit）；删旧 target 与依赖；基准测试改依赖 | T202 | US1-AC2 |
| T205 [P] | VoxApplication | 依赖改为 VoxKit / Bridge | T204 | US1-AC2 |
| T206 [P] | VoxPresentation | 同上 | T204 | US1-AC2 |
| T207 | App 壳 + scripts/tests | import、`project.yml`、harness 依赖 | T205, T206 | US1-AC2 |
| T208 | .github | red lines 全量范围；fixture 构建（macOS + iOS Simulator） | T203, T207 | US4-AC3, US2-AC4 |
| T209 | docs | tech-context/frontmatter/AGENTS | T208 | US7-AC2 |
| GATE-2 | — | golden 全组相等；全部 required 绿 | T209 | US1-AC1 |
| T210 | 线上 | merge commit 合并后在 `main` 上采集 3 个文件的 `git log --follow` 证据，贴 PR 评论 | GATE-2 | US6-AC1 |

## 阶段 3：Workflow（PR-3；SDK 组在前，App 组在后）

| ID | 层 | 任务 | 依赖 | AC |
|---|---|---|---|---|
| T301 | VoxKit | `WorkflowDefinition`（speech/refine 入口）+ Codable + 校验 | T210 | US3-AC1, US3-AC2 |
| T302 | VoxKit | `NodeRegistry` + 内置节点 | T301 | US3-AC2 |
| T303 | VoxKit | Scheduler：分层、并发、通道、失败策略、取消 | T302 | US3-AC4/AC5/AC6 |
| T304 | VoxKit | `WorkflowEvent` | T303 | US2-AC4 |
| T305 | VoxKit | `@WorkflowBuilder` + `Preset.overriding` | T304 | US3-AC1 |
| T306 | VoxKit | 内置 presets（含 `VoxWorkflowWhisperKit`） | T305 | US3-AC7 |
| T307 | VoxKit | SDK 侧 golden（复制 fixture + drift 检查）+ 金丝雀全 preset | T306 | US1-AC1, US3-AC3, US4-AC2 |
| T308 | VoxInfrastructure/Bridge | `StageModelSettings` → preset 映射 + 全组合测试；`WorkflowTranscriptionCoordinator`（转发 `ModelLoadingStartControlling`）；`RefineWorkflowRunner`；iOS 偏好映射与通知重应用 | T307 | US3-AC3, US1-AC3 |
| T309 | VoxApplication | `DefaultRefinementUseCase` 只依赖 `RefineWorkflowRunning` | T308 | US1-AC2 |
| T310 | App 壳（含 VoxPocketTests、scripts/tests） | 同一 commit：删除 `injectMergerIfNeeded`/transcriber 分支/`TranscriberProvider`/`DefaultStageTextModelService`/`StageModelRouting.applyTextModels` 等（RB-8/RB-9）；golden (b) 改由 preset 导出 `pipeline`；每栈独立 runtime；iOS `ServiceContainer` 改接 iOS 映射；选择测试迁为 preset 测试（矩阵不缩小）；harness 同步 | T309 | US1-AC4, US1-AC7 |
| T311a | VoxInfrastructure | 基准测试改用 public refine workflow / preset API | T310 | US1-AC2 |
| T311 | VoxKit | `DefaultLLMService`/`LLMService` 降为 `package`；API 快照更新 | T311a | US2-AC4 |
| T312 | docs | tech-context、CLAUDE preset 表 | T311 | US7-AC2 |
| GATE-3 | — | golden 按 RB-12 规则相等（含 EB-7 iOS 行）；全部 required 绿，含 App macOS 与 iOS build | T312 | US1-AC1 |

## 阶段 4：拆 repo

| ID | 仓 | 任务 | 依赖 | AC |
|---|---|---|---|---|
| T401 | 临时 clone | filter-repo 导出（`--no-tags`、`(#NN)` 改写），树一致性检查 | GATE-3 合并 | US6-AC1 |
| T402 | 临时 clone | 隐私预检（含音频 blob、作者列表），计数报告交 Owner；按 Q2 处置并重跑 | T401 | US6-AC2 |
| T403 | VoxKit | 建 `LeePepe/VoxKit`（public，MIT），推 `main` | T402 + Owner 确认 | — |
| T404 | VoxKit | `repo-kit init` PR（AGENTS/CLAUDE/verify/hooks/ci/review/PR 模板/CODEOWNERS/tech-context/`ai/`）；`audit` 零发现 | T403 | US6-AC3 |
| T405 | VoxKit | ruleset old→new 给 Owner，批准后设置并回读 | T404 | US6-AC3 |
| T406 | VoxKit | tag（按 Q6）+ release notes；外部消费者 exact 版本验证（macOS + iOS Simulator） | T405 | US6-AC4, US2-AC1 |
| T407 | VoxPocket（E2） | 所有 manifest + `project.yml` 同一 commit 切到远程 exact；删除 `Packages/VoxKit` | T406 | US6-AC5 |
| T408 | VoxPocket | `.gitignore` 放行并提交 4 个 `Package.resolved` | T407 | US6-AC5 |
| T409 | VoxPocket | CI 删 VoxKit lane 与 SDK red lines；golden drift 检查改为对比 pin 版本 tag 中的副本；ruleset 映射文件 | T408 | US6-AC5 |
| T410 | VoxPocket | `check_frontmatter.py` 外部化；宪法/tech-context/AGENTS Dependencies 段与本地覆盖说明 | T409 | US7-AC1, US7-AC2 |
| GATE-4 | — | 全部既有测试 + App 侧 golden (b) 通过 | T410 | US6-AC5 |
| T411 | VoxPocket | 合并后 ruleset apply（Owner 批准）；revert 演练分支 CI 绿后关闭 | GATE-4 | US6-AC6 |

## 关键路径

T001 → T002 → T101 → T102 → T103 → T104 → T107 → T110 → T114 → T115 → GATE-1 → T117 → T201 → T202 → T204 → GATE-2 → T210 → T301 → T307 → T308 → T310 → GATE-3 → T401 → T402 → T404 → T406 → T407 → GATE-4 → T411
