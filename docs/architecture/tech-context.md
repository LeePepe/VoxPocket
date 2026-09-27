---
layer: _root
role: 全局架构总览与 layer 划分;声明层内轴的类角色词表 canonical_roles
canonical_roles: [Types, Config, Repo, Service, Runtime, UI]
support:
  - patterns: ["*.md", "LICENSE", "docs/**", "specs/**", "design/**", "artifacts/**", ".claude/**", ".codex/**", ".specify/**"]
    reason: documentation, specs, design records and agent/tool configuration; checked by docs lints and the contract audit
  - patterns: [".github/**", ".githooks/**", "scripts/**", "tests/**", "fastlane/**", "docker/**", ".gitignore", ".gitleaks.toml", "config.example.json"]
    reason: CI, hooks, policy, release and local tooling; verified by scripts/verify --policy and CI
red_lines:
  - 依赖方向永远向下,任何反向依赖(层间或层内)都是红线(宪法 II)
  - VoxDomain 不得引入任何外部依赖或其他本地 layer
  - 用户语音/转写/精炼文本严禁进入日志或遥测负载(宪法 IV)
---

# VoxPocket 顶层 Tech Context

这是**目录索引层**的技术总览。层间依赖图与详细职责已在同目录既有文档中维护,本文件不复制,
只做指针 + 声明**层内轴**所需的 `canonical_roles`。

## 既有架构文档(权威来源)

- 包架构梳理:[`packages-architecture.md`](./packages-architecture.md)
- 依赖关系图(mermaid):[`dependency-graph.md`](./dependency-graph.md)
- 快速索引:[`../index.md`](../index.md) · 记录索引:[`../records/index.md`](../records/index.md)

## Layer 划分(inter-layer 轴,权威事实源 = 各层 frontmatter 的 `depends_on`)

```
VoxPresentation → VoxApplication → VoxInfrastructure → LokiKit(外部) → VoxDomain
VoxUITesting(standalone,不参与运行时依赖链)
```

| Layer | 一句话职责 | tech-context | depends_on |
|---|---|---|---|
| VoxDomain | 纯领域模型(CoreModels, TextHistory),无外部依赖 | `Packages/VoxDomain/tech-context.md` | (无) |
| VoxInfrastructure | 转写 / LLM / 持久化 / 平台适配 / 偏好 | `Packages/VoxInfrastructure/tech-context.md` | VoxDomain, LokiKit(ext) |
| VoxApplication | UseCases 业务编排 | `Packages/VoxApplication/tech-context.md` | VoxDomain, VoxInfrastructure, LokiKit(ext) |
| VoxPresentation | SwiftUI 视图与 ViewModel | `Packages/VoxPresentation/tech-context.md` | VoxDomain, VoxInfrastructure, VoxApplication, LokiKit(ext) |
| VoxUITesting | 快照测试 · Claude Vision UI 评估(standalone) | `Packages/VoxUITesting/tech-context.md` | (无) |
| VoxPocketApp | Xcode App 壳(`VoxPocket/**`、`VoxPocketWidget/**`):组装、入口、交付 | `VoxPocket/tech-context.md` | VoxDomain, VoxInfrastructure, VoxApplication, VoxPresentation, AppleUITesting(ext), LokiKit(ext) |

> **LokiKit 是外部包**:源自 `LeePepe/shared-telemetry`,本地放在仓库同级 `../LokiKit`
> (`Packages/*` 以 `../../../LokiKit` 引用);CI 由 `scripts/ci/fetch-external-deps.sh` 按固定 SHA
> 取出。不受本仓库门禁约束。各层 frontmatter 的 `depends_on` 只列**仓库内**的本地 layer;
> 外部依赖在正文与上表 `(ext)` 标注,不进 `depends_on`。

> **App 壳是 `VoxPocketApp` layer**:`VoxPocket/**`(`ServiceContainer`、`AppDelegate`、`project.yml`
> 等)与 `VoxPocketWidget/**`。其 `xcodebuild` 全量构建(分钟级)只在 CI 执行,本地 pre-push 不跑
> (`RUN_HEAVY=1` 可显式开启),见 `VoxPocket/tech-context.md`。

每个受版本控制的路径恰好属于一个 layer 的 `owns`,或上方 frontmatter 的一个 `support` 排除项;
`scripts/verify` 用 shared-ci resolver 按此选择 layer 并执行其 `gate`。

## 层内轴:canonical_roles(类角色的依赖顺序)

`canonical_roles: [Types, Config, Repo, Service, Runtime, UI]` —— 这是**类/模块的架构角色**
(stereotype)的依赖顺序,**不是包依赖**。同一原则"依赖只能向下":一个 `Types` 角色的类不得
import `Repo`/`Service`/`UI` 角色的类;反过来允许。

每个 layer 的 `tech-context.md` 在 `roles:` 里从这个词表**取子集**,映射到该层真实存在的目录。
防腐脚本校验:角色名必须在本词表内,且映射的目录真实存在。项目可增删改本词表,校验逻辑不变。

角色语义(本项目约定):

| 角色 | 含义 | 典型目录/前缀 |
|---|---|---|
| Types | 领域模型 / 值类型 / 协议契约 / 设计 token | Models, Protocols, ViewStates, DesignSystem |
| Config | 静态配置 / 偏好 | Preferences, *AppConfig |
| Repo | 持久化 / 外部数据源 / 平台适配器 | Persistence, PlatformAdapters, Providers |
| Service | 业务服务 / 协调器 / LLM·转写服务 | Services, UseCases, Utilities |
| Runtime | 运行时编排 / ViewModel / 布局 | ViewModels, Snackbar |
| UI | SwiftUI 视图 / 组件 | Views, Components |

## Agent 工作方式

改哪层先读哪层的 `tech-context.md`(渐进展开)。改动跨 2+ layer = 太大 = 按 layer 拆。
读取契约与 layer 索引见根目录 [`AGENTS.md`](../../AGENTS.md)。
