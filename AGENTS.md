# AGENTS.md

Last-Reviewed: 2026-09-14

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
swift build --package-path Packages/VoxDomain
swift test --package-path Packages/VoxPresentation
swift test --package-path Packages/VoxApplication
```

## App Build 与交付（TestFlight 唯一渠道）

- **当前平台范围（2026-09-14）**：仅推进 macOS；暂停 iOS 功能开发和 TestFlight 发布，
  恢复须用户明确要求。保留 iOS 代码、既有产物及 required 兼容性检查，不借暂停删除数据或放宽门禁。
- **交付**：所有供用户使用的 macOS / iOS App build 统一经 `testflight.yml` 构建并分发到
  TestFlight；不再在主工作目录或 linked worktree 自动生成本地 App build / archive。
- **安装**：由用户通过 TestFlight 安装；Agent 不主动安装、替换或启动交付 build。
- **验证**：本地保留受影响 layer 的 SPM build/test 与快速检查；App target 的
  `xcodebuild` 验证继续由 CI required 执行，不作为本地交付步骤。
- **发布边界**：提交不等于发布；沿用分支 → PR → required checks → 合并流程。
  TestFlight 自动发布已暂停，仅在用户明确要求后通过 `workflow_dispatch` 手动发布。
- **完成条件**：代码任务报告 commit 与验证结果；Agent 监督 PR 合并和获授权的 macOS
  TF 构建上传，报告版本/build number、run 链接与分发警告。Apple Connect／TestFlight 的
  最终可测试性由用户核实；Agent 不自行登录或查找 ASC 凭据，不把上传成功等同于可测试。
  保留已有本地产物，不自动清理。

## Engineering Rules

- **模型配置 / 启动入口**：修改时先读 `docs/architecture/private-model-config.md`（含启动交互回归命令）；私密配置只在沙箱运行时读取，模板才入库，交付前检查安装包不含私密文件。

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
  required checks 全绿（`SPM <pkg>`×5 / `App target` / `Lint & policy` / `codex-review-target`）后，
  非 draft PR 由 auto-merge 自动 squash 合并。发布走 `testflight.yml`（仅在用户明确要求后手动触发；
  详见 CLAUDE.md → TestFlight Manual Release）。
  `claude-review` 已暂停;`kimi-review` 只发 advisory comment,不参与合并门。
- **pre-commit / pre-push**（本地，可绕过）：只跑快门禁——改到的 layer 增量 build+test、
  frontmatter 防腐校验、"改代码必带测试"。目标 < 60s。脚本在 `scripts/gates/`，经 `.local-review.yml` 接入。
- **CI required**（服务端，不可绕过）：全量 per-package 测试 + app-target `xcodebuild` + frontmatter 校验，
  锁定 Xcode 版本。重验证（xcodebuild/模拟器）只在这里，不进 pre-push。Codex 是 required
  review;Kimi 的结果只供参考,不能满足或阻塞 required gate。
  Required-check policy 镜像在 `scripts/rulesets/main-protection.json`,线上 ruleset
  变更必须同步该文件。
  `codex-review-target.yml` 是 required AI 控制面；旧 `pull_request` workflow 已停用。
  线上 ruleset 通过 `scripts/rulesets/apply` 与同目录 JSON 同步。
- **防腐**：`scripts/gates/check_frontmatter.py` 校验每层 frontmatter 与代码一致（layer 名、`depends_on`
  双向、`roles` 角色词表与目录/前缀）。架构变了就更新 tech-context，别绕过。
- 既有 `local-review-skill`（Codex 审查）hook 保留，与上述快门禁并行。

## 主工作目录修改记录

- 2026-09-10：修复配置预加载导致的主队列饥饿；入口同步启动，服务等待异步配置。补充生产入口交互回归和启动状态测试。
- 2026-09-11：按用户要求改为 TestFlight 唯一 App build 交付渠道，取消自动本地归档与主动安装。

## GitHub 身份（原生 Git / gh）

- 本个人仓库：`LeePepe/VoxPocket`（ID `1197276028`）；Git 与 gh 的预期认证账号均为 `LeePepe`。提交署名不是认证。
- 当前 GitHub remote：`origin`。新 clone/worktree/Multica checkout 须重新核对实际 fetch/push URL；
  本地 origin、其他 fork/upstream 或未知归属不能套用本账号，先问 Owner。
- gh 使用 `$HOME/.config/github-identity/profiles/LeePepe` 的独立无凭据 profile，复用已有 keyring。
  本文所有 gh 命令（含其他章节示例）均加下列调用前缀；仓库命令显式 `--repo LeePepe/VoxPocket`，
  API 显式指定 host/仓库路径。`--repo` 不会选择账号；共享配置中不使用 `gh auth switch`。
- 本仓库已指定账号/profile：每次 gh 调用直接用 `env -u GH_TOKEN -u GITHUB_TOKEN` 排除环境覆盖，
  无需确认被排除变量的来源，也不因其存在暂停。只影响该子进程，不读取或输出 token，不改父环境或凭据。
  profile 不可用或核验失败时停止，不回退到环境 token 或共享默认账号；核验通过即按既有任务授权继续。
  每次写前用同一 profile 核对 `/user` 的 login、仓库 full_name/ID 与所需权限，
  任一不符立即停止。凭据登录/生成/轮换、服务重启交 Owner，不进入自动恢复流程。
- 当前 checkout 或新工作区首次使用前检查 Git 的有效认证配置。以下原生配置仅在目标已核验、旧 helper
  无冲突后应用；保留旧值用于回滚，不改全局 Git、署名或 hooks。启用独立 config.worktree 时检查覆盖，
  需要只影响该工作区则用 `--worktree`；AGENTS 不会自动安装 local config。

```bash
# 原生 gh 调用形状；先检查 /user，再同前缀检查 repos/LeePepe/VoxPocket 的 id/full_name/permissions。
env -u GH_TOKEN -u GITHUB_TOKEN -u GH_REPO -u GH_HOST \
  GH_CONFIG_DIR="$HOME/.config/github-identity/profiles/LeePepe" \
  gh api --hostname github.com user --jq .login

# HTTPS 目标路径级 Git helper；已有不同 helper、pushurl、URL rewrite 或 HTTP 认证覆盖时先停下来核对。
git config --local credential.https://github.com.useHttpPath true
git config --local --replace-all credential.https://github.com/LeePepe/VoxPocket.git.helper ''
git config --local --add credential.https://github.com/LeePepe/VoxPocket.git.helper \
  '!env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/github-identity/profiles/LeePepe" gh auth git-credential'
git config --local credential.https://github.com/LeePepe/VoxPocket.git.username LeePepe
```

只读验证使用 `git ls-remote <已核验 remote> HEAD`；不要打印 `git credential fill` 或 `gh auth token`
的输出。核验通过后才执行获授权的原生 `git push` / `gh pr …`，不把只读权限检查当成写入成功。
