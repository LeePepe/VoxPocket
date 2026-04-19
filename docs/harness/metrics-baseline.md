# Harness Metrics Baseline

Last-Reviewed: 2026-04-16
Owner: VoxPocket Engineering
Cadence: Weekly snapshot (every Tuesday)

## Scope

Phase 0 只定义“可度量合同”，不追求一次性把所有指标数据都拉齐。无法直接采集的指标必须写入 `null` 和原因。

## Baseline Metrics

### 1. PR cycle time
- Name: `prCycleHours`
- Definition: `merged_at - opened_at` (hours)
- Source: GitHub Pull Requests API (`opened_at`, `merged_at`)
- Target bands:
  - Good: `<= 24h`
  - Warning: `> 24h && <= 72h`
  - Alert: `> 72h`

### 2. Test rerun rate
- Name: `rerunRate`
- Definition: `retried_suites / total_suites`
- Source: `artifacts/reports/test-report.json` (`totals.retried`, `suites.length`)
- Target bands:
  - Good: `<= 0.10`
  - Warning: `> 0.10 && <= 0.25`
  - Alert: `> 0.25`

### 3. Doc freshness score
- Name: `docFreshness`
- Definition: `fresh_critical_docs / total_critical_docs`
- Source: `scripts/docs/lint_docs_freshness.sh` 输出汇总
- Target bands:
  - Good: `>= 0.95`
  - Warning: `>= 0.80 && < 0.95`
  - Alert: `< 0.80`

### 4. Architecture violation count
- Name: `archViolationCount`
- Definition: 每次检查中结构性依赖违规数量
- Source: Phase 2 结构 lint 结果文件（预留，当前可为空）
- Target bands:
  - Good: `0`
  - Warning: `1-3`
  - Alert: `> 3`

## Snapshot Contract

每次快照使用 `docs/harness/templates/metric-snapshot-template.json` 的字段结构，写入：
- `artifacts/harness/metrics/YYYY-MM-DD.snapshot.json`

## First Snapshot

- Snapshot path: `artifacts/harness/metrics/2026-03-31.snapshot.json`
- Generated at: `2026-03-31`
- Caveats:
  - `prCycleHours`: local scaffold 中暂未集成 GitHub API
  - `docFreshness`: 以本地 freshness lint 结果为准；未执行时返回 `null`
  - `archViolationCount`: 结构 lint 尚未在 Phase 0/1 上线，先记录为 `null`
