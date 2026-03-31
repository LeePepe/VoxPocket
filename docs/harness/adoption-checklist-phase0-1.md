# Harness Phase 0-1 Adoption Checklist

Last-Reviewed: 2026-03-31
Owner: VoxPocket Engineering

## Baseline Metrics
- [x] `docs/harness/metrics-baseline.md` 已定义 4 个核心指标
- [x] `docs/harness/templates/metric-snapshot-template.json` 已建立
- [x] baseline collector 脚本已提供 dry-run 和落盘模式

## First Snapshot
- [x] 已生成首个 snapshot 文件（`artifacts/harness/metrics/2026-03-31.snapshot.json`）
- [ ] PR cycle time 的 GitHub API 数据链路待接入
- [ ] arch violation 指标待 Phase 2 结构 lint 上线

## System Of Record
- [x] `AGENTS.md` 已改为 map 样式入口
- [x] `docs/index.md` 与 `docs/records/index.md` 已双向链接
- [x] 关键文档索引与 debt tracker 已落盘

## Governance
- [x] docs map lint 已接入
- [x] docs freshness lint 已接入
- [x] `docs-governance` workflow 已创建
- [x] 本地 review 已加入 docs lint 命令

## Known Gaps
- [ ] docs freshness 元数据覆盖率持续治理
- [ ] 关键指标采集自动化（GitHub API）
