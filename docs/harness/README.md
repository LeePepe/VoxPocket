# Harness Engineering Notes

Last-Reviewed: 2026-03-31

本目录用于落地 OpenAI Harness Engineering 思路的“控制面”改造（文档系统、可度量基线、反馈回路），不包含业务功能代码。

## Phase 0 (Baseline)

- 指标定义：`docs/harness/metrics-baseline.md`
- 快照模板：`docs/harness/templates/metric-snapshot-template.json`
- 快照历史约定：`docs/harness/metrics-history/README.md`

## Baseline Collection

```bash
# dry run: 仅打印，不落盘
zsh scripts/docs/collect_harness_baseline.sh \
  --window-start 2026-03-01 \
  --window-end 2026-03-31 \
  --dry-run

# real run: 生成快照文件
zsh scripts/docs/collect_harness_baseline.sh \
  --window-start 2026-03-01 \
  --window-end 2026-03-31
```

输出路径：`artifacts/harness/metrics/YYYY-MM-DD.snapshot.json`
