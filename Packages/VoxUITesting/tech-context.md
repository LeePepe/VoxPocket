---
layer: VoxUITesting
role: 独立测试工具包 —— 快照功能测试与 Claude Vision UI 评估,不参与运行时依赖链
depends_on: []
depended_by: []
red_lines:
  - standalone 包,禁止依赖任何 Vox* 运行时 layer(保持测试工具与被测代码解耦)
  - CLAUDE_API_KEY/ANTHROPIC_API_KEY 来自环境变量,禁止硬编码(宪法 V)
  - 严格并发已开启(StrictConcurrency),禁止用 @unchecked 绕过编译检查(宪法 III)
roles:
  Repo:    [ScreenCapture, SnapshotHelpers]
  Service: [AgentEvaluator, EvalReport, PerformanceHelpers, ViewInspectorHelpers]
test: swift test --package-path Packages/VoxUITesting
owns: [VoxFunctionalTest, VoxAgentEval]
---

# VoxUITesting Tech Context

## 职责
独立测试基础设施(standalone,不在运行时依赖链上)。两个 target:
- **VoxFunctionalTest**:基于 `swift-snapshot-testing` 的快照/功能测试助手
  (SnapshotHelpers / ViewInspectorHelpers / PerformanceHelpers)。
- **VoxAgentEval**:Claude Vision 驱动的 UI 评估(ScreenCapture / AgentEvaluator / EvalReport)。

## 依赖
- **仓库内**:无(刻意与 Vox* 运行时包解耦)。
- **外部**:`swift-snapshot-testing`。两 target 均开启 `StrictConcurrency` 实验特性。

## 约束 / 红线投影
- **secrets**:`CLAUDE_API_KEY`/`ANTHROPIC_API_KEY` 走 env。
- **解耦**:作为测试工具,不反向依赖被测运行时 layer;`depends_on` 恒为空。

## 层内轴
`Repo(ScreenCapture/SnapshotHelpers)` 采集,`Service(AgentEvaluator/EvalReport/*Helpers)` 消费;
Service 依赖 Repo 合法(向下),反向即违规。
