# Documentation Freshness Policy

Last-Reviewed: 2026-03-31
Owner: VoxPocket Engineering

## Policy Goal

关键文档必须保持“可被智能体信任”：
- 有明确责任人
- 有最近审阅日期
- 超过时效会被 lint 报错

## Metadata Contract

关键文档必须包含：
- `Last-Reviewed: YYYY-MM-DD`

可选：
- `Owner: <team or person>`
- `Freshness-Exempt: true`（用于冻结文档）

## Critical Docs And SLA

- `AGENTS.md` - 30 days
- `docs/index.md` - 30 days
- `docs/records/index.md` - 30 days
- `docs/harness/metrics-baseline.md` - 14 days
- `README.md` - 60 days

## Exception Rule

如果文档为历史冻结材料，可加：
`Freshness-Exempt: true`

lint 会跳过该文件的时效检查，但仍会检查文件存在性。
