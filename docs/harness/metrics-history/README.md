# Metrics History Convention

Last-Reviewed: 2026-03-31

该目录约定用于保存“历史快照约束”，实际快照文件放在 `artifacts/harness/metrics/`。

命名规范：
- `YYYY-MM-DD.snapshot.json`

建议：
- 每周固定生成一次
- 如果某指标无法采集，必须保留 `null` 并写明 `reason`
