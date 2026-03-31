# VoxPocket 多 Agent 测试自动化设计

日期：2026-03-31  
状态：Draft（待 Spec Reviewer 与用户最终确认）  
范围：测试自动化体系（单测/集成/UI/语音/E2E/性能）与执行编排，不包含业务功能改造。

## 1. 背景与目标

VoxPocket 当前已有部分单元测试与少量 UI 测试骨架，但在以下方面缺口明显：

- UI 自动化仍接近模板状态，关键控件缺少稳定标识。
- 语音链路自动化以手工验证为主，缺少可重复质量基线。
- 缺少统一执行与聚合层，跨模块回归成本高。

本设计目标：

1. 建立“模块负责完善测试 + 全局负责执行”的多 agent 体系。  
2. 在 GitHub Actions 上落地 `PR + Nightly` 双流水线。  
3. 同时覆盖功能正确性、用户视角 E2E、语音质量、性能回归。  
4. 将截图采集与可选 OCR 归档纳入统一产物，提升问题定位效率。

## 2. 非目标

- 不在本阶段重构业务架构。
- 不引入额外 CI 平台（仅 GitHub Actions）。
- 不在本阶段扩展到 Android/Web 客户端。

## 3. Agent 拓扑与职责

采用 `5 个改进 agent + 1 个执行 agent`：

1. `automation-test-improver`  
2. `ui-test-improver`  
3. `voice-test-improver`  
4. `performance-test-improver`  
5. `test-executor`（全局执行编排）

说明：

- E2E 用户旅程不单设独立 agent；由 `ui/voice/automation` 共同维护用例内容。  
- `test-executor` 统一编排执行 E2E、汇总结果与产物。

### 3.1 详细职责边界

`automation-test-improver`

- 负责：单元/集成测试完善、跨层业务流程断言、Fake/Mock 与测试工具。  
- 不负责：XCUITest、语音质量阈值、性能预算。

`ui-test-improver`

- 负责：SwiftUI/XCUITest、`accessibilityIdentifier` 体系、截图断言策略。  
- 不负责：语音识别质量判定、性能阈值定义。

`voice-test-improver`

- 负责：语音离线回归、音频夹具与标注文本、CER/WER 规则。  
- 不负责：UI 交互编排、性能预算。

`performance-test-improver`

- 负责：性能用例、基线维护、回归阈值策略与趋势数据。  
- 不负责：功能正确性断言。

`test-executor`

- 负责：统一执行编排、重试策略、结果聚合、artifact 上传、告警。  
- 不负责：新增测试业务逻辑（仅执行与治理）。

## 4. 交付契约（统一接口）

每个 improver 产出的测试资产必须包含以下契约字段：

- `manifest`：入口命令、标签、预估时长、依赖。  
- `owner`：模块归属（agent/代码owner）。  
- `flakyPolicy`：是否可重试、最大重试次数。  
- `artifactsContract`：日志、截图、质量报告、性能数据路径。  

统一契约目的是让 `test-executor` 可以无条件编排，而不依赖模块内部细节。

## 5. CI 编排（GitHub Actions）

### 5.1 PR Pipeline（快速反馈）

目标时长：10-20 分钟。

执行集合：

- 核心单元/集成快集。
- UI smoke（关键 1-2 条用户旅程）。
- 语音离线 smoke（小样本夹具）。
- 性能 smoke（启动时延、首段转写时延）。

规则：

- 失败阻断合并。
- 必须输出失败摘要与必要 artifact。

### 5.2 Nightly Pipeline（高覆盖与趋势）

触发：每日定时运行。

执行集合：

- 全量单元/集成。
- 全量 UI 场景与截图采集。
- 语音全量夹具与 CER/WER 评估。
- 全量 E2E 用户旅程。
- 全量性能测试与基线差异分析。

规则：

- 失败不阻断日常开发，但必须产出告警与回归报告。  
- 连续 3 天同类失败自动升级为高优先级治理项。

## 6. E2E（用户视角）策略

E2E 明确纳入体系，执行权在 `test-executor`，内容权在三方 improver。

关键场景最小集合：

1. 启动应用 -> 新建会话 -> 进入录音入口 -> 产生文本 -> 会话落库。  
2. 历史会话检索 -> 打开详情 -> 复制/查看原文。  
3. 快速录音入口（macOS）-> 结束 -> 结果可追踪。  

执行策略：

- PR：仅跑关键 E2E smoke。  
- Nightly：跑全量 E2E。

## 7. 语音测试策略

语音专项使用“双层测试”：

1. 确定性离线测试（主力，PR/Nightly 均跑）  
2. 更高成本链路回归（Nightly 全量）

核心要求：

- 固定音频夹具集（zh-Hans 主场景，含静音/噪音/长短句）。  
- 每个夹具有标注文本。  
- 输出 `CER/WER` 与阈值判定。  
- 失败时保存识别文本、评分与日志，便于回归归因。

## 8. 性能测试策略

性能专项由 `performance-test-improver` 维护，`test-executor` 统一执行。

指标集合：

- 启动时延。  
- 录音开始到首段文本出现时延。  
- 完整转写耗时。  
- 内存峰值与 CPU 占用（可按场景采样）。

执行策略：

- PR：仅 `perf-smoke`。  
- Nightly：`perf-full` + 历史基线 diff。

## 9. 截图获取与归档策略

截图是 UI/E2E 失败定位的一等公民：

- PR：关键失败步骤截图。  
- Nightly：关键步骤常规截图 + 失败补充截图。  
- 统一目录：`artifacts/screenshots/`。

可选扩展（用于自动化分析）：

- 对截图执行 OCR（Vision）并生成 `ocr-snapshots/`。  
- 将 OCR 文本与用例步骤关联，辅助定位“UI 显示与预期不一致”类问题。

## 10. 失败处理与治理

PR 失败：

- 阻断合并。  
- 必须修复或临时降级用例并留存治理工单。

Nightly 失败：

- 不阻断开发。  
- 下一工作日完成归因（代码回归/环境波动/测试自身问题）。  
- 连续 3 天同类失败自动升级治理优先级。

## 11. 分阶段落地计划

Phase 1（1 周，先跑起来）

- 建立 PR/Nightly workflow 骨架。  
- 接入 `test-executor` 聚合与报告。  
- 跑通最小 smoke（单测/UI/语音/性能）。

Phase 2（1-2 周，补覆盖）

- 四类 improver 完善各自测试资产。  
- 建立截图 artifact 与失败强制上传。  
- 建立语音与性能基线。

Phase 3（持续治理）

- flaky 自动识别与重试统计。  
- Nightly 回归自动归因到模块 owner。  
- 持续收紧阈值与提升稳定性。

## 12. 验收标准

满足以下条件即视为该设计可进入 implementation planning：

1. GitHub Actions 中可见 `PR + Nightly` 两条流水线定义。  
2. 六类测试能力均有可执行入口：单测、集成、UI、语音、E2E、性能。  
3. `test-executor` 可统一汇总并输出标准化 artifact。  
4. PR 可阻断回归，Nightly 可持续输出趋势与告警。  
5. 各 improver 与 executor 的职责边界清晰，无重叠冲突。

