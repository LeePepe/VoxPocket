# AGENTS.md

Last-Reviewed: 2026-07-15

## Project Snapshot

VoxPocket 是 macOS/iOS 的 SwiftUI 语音转写应用，默认语音识别语言为 `zh-Hans`，并支持 Apple Intelligence 文本精炼。

## Layered Architecture

```
VoxPresentation  ->  VoxApplication  ->  VoxInfrastructure + LokiKit  ->  VoxDomain
```

- `VoxDomain`: 纯领域模型（`CoreModels`, `TextHistory`）
- `VoxInfrastructure`: 转写、LLM、持久化、平台适配、偏好设置
- `LokiKit`: 独立可观测性/遥测包（日志、监控、Loki telemetry）
- `VoxApplication`: UseCases 业务编排
- `VoxPresentation`: SwiftUI 视图与 ViewModel

## Start Here

- Fast index: `docs/index.md`
- Records index (source of truth map): `docs/records/index.md`
- Architecture docs: `docs/architecture/`
- Harness baseline: `docs/harness/metrics-baseline.md`

## Build And Test

```bash
xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build
swift build --package-path Packages/VoxDomain
swift test --package-path Packages/VoxPresentation
swift test --package-path Packages/VoxApplication
```

## Engineering Rules

- 协议驱动 DI，默认实现用 `Default*` 命名。
- 测试替身使用 `Fake*` / `Mock*` 命名。
- 不向 `VoxDomain` 引入外部依赖。
- 变更前后优先保持分层依赖方向不变。

## Agent 读取契约（Read Contract）

任务开始前，按你要碰的东西先读对应文档 —— 不读就动手 = 违规。

| 你要做的事 | 必读（前置） | 拿什么 |
|---|---|---|
| 任何任务 | `.specify/memory/constitution.md` | 不可违反的红线（先确认不踩） |
| 决定做什么 / 改需求 | `.specify/`（spec-kit：`/speckit-specify` → `specs/`）；历史计划见 `docs/plans/` | 功能意图、验收标准、范围边界 |
| 改全局架构 / 跨层设计 | `docs/architecture/tech-context.md`（+ `packages-architecture.md`、`dependency-graph.md`） | 架构决策、数据流、layer 划分、`canonical_roles` |
| 改 `Packages/<pkg>/**` | `Packages/<pkg>/tech-context.md` | 该层职责 / 依赖 / 红线 / 测试命令 |
| 改 `VoxPocket/VoxPocket/**`（app 壳） | `docs/architecture/tech-context.md` 的 app-target 小节 | 该处不是 layer，验证归 CI（xcodebuild） |

## Layer 索引（Layer Map）

| Layer | 职责（一句话） | 文档 | 依赖（本地） |
|---|---|---|---|
| VoxDomain | 纯领域模型（CoreModels, TextHistory），无外部依赖 | `Packages/VoxDomain/tech-context.md` | （无） |
| VoxInfrastructure | 转写 / LLM / 持久化 / 平台适配 / 偏好 | `Packages/VoxInfrastructure/tech-context.md` | VoxDomain（+ ext LokiKit） |
| VoxApplication | UseCases 业务编排 | `Packages/VoxApplication/tech-context.md` | VoxDomain, VoxInfrastructure（+ ext LokiKit） |
| VoxPresentation | SwiftUI 视图与 ViewModel | `Packages/VoxPresentation/tech-context.md` | VoxDomain, VoxInfrastructure, VoxApplication（+ ext LokiKit） |
| VoxUITesting | 快照测试 · Claude Vision UI 评估（standalone） | `Packages/VoxUITesting/tech-context.md` | （无） |

> **LokiKit** 是外部包（`~/Development/LokiKit`），不在本仓库、不进 `depends_on`、不受本仓库门禁约束。
> **`VoxPocket/VoxPocket/`** 是 Xcode app 壳，不是 layer；其 `xcodebuild` 全量验证归 CI required。

**渐进展开**：先读本表定位相关 layer → 只下钻该 layer 的 `tech-context.md` → 拿约束再动手。
不预读所有 layer 文档。改哪层读哪层。

**按 layer 收窄范围**：
- 改动只落 1 个 layer → 一个任务直接做。
- 跨 2+ layer → 太大，按 layer 拆成 N 个独立可 build/test 的子任务（一层一 commit）。
- 单层内仍很大 → 按技术切面再拆（纯逻辑 → 校验 → 编排 → 输出转换 → fixture → 文档 → 迁移）。
- 收尾遗留记为新任务，不回头扩大当前任务。

## 分层修复约定

失败信号带 `{layer, red_lines}`。无论谁来修：
- 只在失败所在 layer 内改；根因在别层则记新任务，不跨层改。
- 带着该层 `red_lines` 修（别为了过测试踩红线，尤其"内容进日志/遥测"这条）。
- 修完跑该层 `test`（见各层 frontmatter）验证再交。

## 门禁与防腐

- **PR → main（服务端强制）**：`main` 由 ruleset 保护，**禁止直推**。改动一律走分支 → PR，
  required checks 全绿（`SPM <pkg>`×5 / `App target` / `Lint & policy` / `codex-review`）后，
  非 draft PR 由 auto-merge 自动 squash 合并。发布走 `testflight.yml`（cron 每 6h，有新 commit 才发；
  详见 CLAUDE.md → TestFlight Auto-Release）。
  `claude-review` 已暂停;`kimi-review` 只发 advisory comment,不参与合并门。
- **pre-commit / pre-push**（本地，可绕过）：只跑快门禁——改到的 layer 增量 build+test、
  frontmatter 防腐校验、"改代码必带测试"。目标 < 60s。脚本在 `scripts/gates/`，经 `.local-review.yml` 接入。
- **CI required**（服务端，不可绕过）：全量 per-package 测试 + app-target `xcodebuild` + frontmatter 校验，
  锁定 Xcode 版本。重验证（xcodebuild/模拟器）只在这里，不进 pre-push。Codex 是 required
  review;Kimi 的结果只供参考,不能满足或阻塞 required gate。
  Required-check policy 镜像在 `scripts/rulesets/main-protection.json`,线上 ruleset
  变更必须同步该文件。
- **防腐**：`scripts/gates/check_frontmatter.py` 校验每层 frontmatter 与代码一致（layer 名、`depends_on`
  双向、`roles` 角色词表与目录/前缀）。架构变了就更新 tech-context，别绕过。
- 既有 `local-review-skill`（Codex 审查）hook 保留，与上述快门禁并行。
