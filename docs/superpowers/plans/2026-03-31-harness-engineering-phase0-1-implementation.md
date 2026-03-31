# Harness Engineering Phase 0-1 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the first two adoption phases of harness engineering for VoxPocket: (Phase 0) define measurable baselines and (Phase 1) establish the repository as a maintainable, agent-readable system of record.

**Architecture:** Keep existing code architecture intact and focus on control-plane improvements: documentation topology, baseline metric contracts, and mechanical checks that keep agent context small and trustworthy. Introduce a lightweight docs governance loop (map, index, freshness checks) without large-scale content migration.

**Tech Stack:** Markdown (`docs/`), `zsh`, `jq`, `rg`, GitHub Actions YAML, existing local-review hooks

---

## File Structure (Planned Changes)

### New files
- `docs/harness/README.md` — Harness adoption scope, principles, and rollout status.
- `docs/harness/metrics-baseline.md` — Baseline metric definitions, collection windows, and acceptance bands.
- `docs/harness/metrics-history/README.md` — Convention for storing periodic metric snapshots.
- `docs/harness/templates/metric-snapshot-template.json` — Stable JSON schema template for snapshots.
- `docs/records/README.md` — System-of-record contract for repository docs.
- `docs/records/index.md` — Canonical map for design/spec/plan/debt/reference docs.
- `docs/records/doc-freshness-policy.md` — Freshness SLA and ownership policy.
- `scripts/docs/lint_docs_map.sh` — Mechanical checks for AGENTS/docs map integrity.
- `scripts/docs/lint_docs_freshness.sh` — Mechanical checks for stale critical docs.
- `.github/workflows/docs-governance.yml` — CI guard for docs map/freshness checks.

### Modified files
- `AGENTS.md` — Reduce to concise map-style entrypoint and links to canonical docs.
- `docs/index.md` — Convert into progressive-disclosure entry and link to `docs/records/index.md`.
- `README.md` — Add “Harness Engineering” section and docs governance entrypoints.
- `.local-review.yml` — Add lightweight docs lint command to `commit` stage (non-blocking threshold can be adjusted).

### Optional (only if low-risk during execution)
- `docs/plans/*` and `docs/superpowers/plans/*` — Add cross-links to the new canonical records index (no bulk moves in Phase 0-1).

---

## Chunk 1: Phase 0 Baseline (Measurability First)

### Task 1: Define baseline metric contract

**Files:**
- Create: `docs/harness/metrics-baseline.md`
- Create: `docs/harness/templates/metric-snapshot-template.json`
- Test: N/A (doc contract + JSON validation)

- [ ] **Step 1: Create failing precheck for missing baseline docs**

Run:
`test -f docs/harness/metrics-baseline.md && test -f docs/harness/templates/metric-snapshot-template.json`

Expected: FAIL (files do not exist yet)

- [ ] **Step 2: Write baseline metric spec doc**

`metrics-baseline.md` must define exactly:
- PR cycle time (`opened_at -> merged_at`) target bands
- test rerun rate (`retried / total suites`) target bands
- doc freshness score (`fresh_critical_docs / total_critical_docs`) target bands
- architecture violation count (`structural lint failures`) target bands
- collection source for each metric (GitHub API or local artifact path)
- weekly snapshot cadence and owner

- [ ] **Step 3: Create snapshot JSON template**

Add schema-like template fields (example keys):
- `generatedAt`
- `window.start`, `window.end`
- `metrics.prCycleHours`
- `metrics.rerunRate`
- `metrics.docFreshness`
- `metrics.archViolationCount`
- `notes`

- [ ] **Step 4: Validate JSON template**

Run:
`jq -e . docs/harness/templates/metric-snapshot-template.json >/dev/null`

Expected: PASS

- [ ] **Step 5: Validate required sections exist in baseline doc**

Run:
`rg -n "PR cycle|rerun rate|doc freshness|architecture violation|cadence|owner" docs/harness/metrics-baseline.md -S`

Expected: PASS with matched lines for all required sections

- [ ] **Step 6: Commit**

```bash
git add docs/harness/metrics-baseline.md docs/harness/templates/metric-snapshot-template.json
git commit -m "docs: define harness baseline metrics contract"
```

### Task 2: Add baseline collection scaffold

**Files:**
- Create: `docs/harness/README.md`
- Create: `docs/harness/metrics-history/README.md`
- Create: `scripts/docs/collect_harness_baseline.sh`
- Test: `scripts/docs/collect_harness_baseline.sh`

- [ ] **Step 1: Create failing precheck for missing collector script**

Run:
`test -x scripts/docs/collect_harness_baseline.sh`

Expected: FAIL

- [ ] **Step 2: Implement baseline collector script (scaffold)**

Behavior requirements:
- accepts `--window-start` and `--window-end`
- supports `--dry-run` (no file write)
- emits snapshot JSON to:
  `artifacts/harness/metrics/<YYYY-MM-DD>.snapshot.json`
- if upstream data unavailable, writes explicit `null` + reason fields (never fake values)

- [ ] **Step 3: Add harness README usage**

Document:
- what Phase 0 tracks
- where snapshots are stored
- how to run dry-run and real collection commands

- [ ] **Step 4: Syntax and dry-run validation**

Run:
- `zsh -n scripts/docs/collect_harness_baseline.sh`
- `zsh scripts/docs/collect_harness_baseline.sh --window-start 2026-03-01 --window-end 2026-03-31 --dry-run`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add docs/harness/README.md docs/harness/metrics-history/README.md scripts/docs/collect_harness_baseline.sh
git commit -m "chore: add harness baseline collection scaffold"
```

### Task 3: Capture first baseline snapshot

**Files:**
- Create: `artifacts/harness/metrics/2026-03-31.snapshot.json` (or current execution date)
- Modify: `docs/harness/metrics-baseline.md` (append first snapshot reference)

- [ ] **Step 1: Run baseline collection**

Run:
`zsh scripts/docs/collect_harness_baseline.sh --window-start 2026-03-01 --window-end 2026-03-31`

Expected: PASS and snapshot file created

- [ ] **Step 2: Validate output structure**

Run:
`jq -e '.generatedAt and .window and .metrics' artifacts/harness/metrics/*.snapshot.json >/dev/null`

Expected: PASS

- [ ] **Step 3: Link snapshot in baseline doc**

Add:
- snapshot path
- generation date
- caveats for null/unavailable metrics

- [ ] **Step 4: Commit**

```bash
git add artifacts/harness/metrics/*.snapshot.json docs/harness/metrics-baseline.md
git commit -m "docs: record initial harness baseline snapshot"
```

---

## Chunk 2: Phase 1 System-of-Record (Map, Not Manual)

### Task 4: Refactor AGENTS/docs into progressive-disclosure map

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/index.md`
- Create: `docs/records/README.md`
- Create: `docs/records/index.md`

- [ ] **Step 1: Create failing line-count gate for AGENTS map size**

Run:
`wc -l AGENTS.md`

Expected: currently exceeds or is near threshold defined for map-style doc (set target <= 140 lines)

- [ ] **Step 2: Rewrite AGENTS as concise map**

Required content:
- project identity and architecture in brief
- “start here” links only (no long operational prose)
- pointer to `docs/records/index.md` as source-of-truth map
- pointer to test/build command index

- [ ] **Step 3: Create canonical records index**

`docs/records/index.md` must include sections linking to:
- architecture docs
- product/spec docs
- active/completed plans
- technical debt tracker location
- references and runbooks

- [ ] **Step 4: Update `docs/index.md` to be minimal entrypoint**

Keep:
- package quick map
- top-level entrypoints
- strong link to `docs/records/index.md`

- [ ] **Step 5: Validate cross-links**

Run:
`rg -n "docs/records/index.md|docs/index.md|AGENTS.md" AGENTS.md docs/index.md docs/records/index.md -S`

Expected: PASS (bi-directional references present)

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md docs/index.md docs/records/README.md docs/records/index.md
git commit -m "docs: convert agents/docs to progressive disclosure map"
```

### Task 5: Introduce docs freshness policy + lint automation

**Files:**
- Create: `docs/records/doc-freshness-policy.md`
- Create: `scripts/docs/lint_docs_map.sh`
- Create: `scripts/docs/lint_docs_freshness.sh`
- Modify: `.github/workflows/docs-governance.yml` (new file in this task)
- Modify: `.local-review.yml`

- [ ] **Step 1: Add freshness policy doc**

Policy must define:
- critical doc list (minimum set)
- freshness SLA (e.g. N days) by doc category
- ownership convention
- exception mechanism for intentionally frozen docs

- [ ] **Step 2: Implement docs map linter**

`lint_docs_map.sh` checks:
- AGENTS line limit
- required links exist
- required key docs exist on disk
- no dead links among controlled docs (best-effort grep checks)

- [ ] **Step 3: Implement freshness linter**

`lint_docs_freshness.sh` checks:
- critical docs carry last-reviewed metadata
- review age does not exceed SLA
- prints actionable failures with exact file path

- [ ] **Step 4: Add CI workflow for docs governance**

Create `.github/workflows/docs-governance.yml`:
- trigger: `pull_request`, `workflow_dispatch`
- run both lints
- upload logs/artifacts on failure

- [ ] **Step 5: Hook local review gate**

In `.local-review.yml`, add to `commit` stage command checks:
- `zsh scripts/docs/lint_docs_map.sh`
- `zsh scripts/docs/lint_docs_freshness.sh`

Set severity policy to avoid over-blocking at first rollout (e.g. warn-first if needed).

- [ ] **Step 6: Validate end-to-end**

Run:
- `zsh -n scripts/docs/lint_docs_map.sh scripts/docs/lint_docs_freshness.sh`
- `zsh scripts/docs/lint_docs_map.sh`
- `zsh scripts/docs/lint_docs_freshness.sh`
- `rg -n "lint_docs_map.sh|lint_docs_freshness.sh" .github/workflows/docs-governance.yml -S`

Expected: PASS (or known policy failures with explicit actionable output)

- [ ] **Step 7: Commit**

```bash
git add docs/records/doc-freshness-policy.md scripts/docs/lint_docs_map.sh scripts/docs/lint_docs_freshness.sh .github/workflows/docs-governance.yml .local-review.yml
git commit -m "ci: add docs governance and freshness lint gates"
```

### Task 6: Document operator workflow and adoption checklist

**Files:**
- Modify: `README.md`
- Create: `docs/harness/adoption-checklist-phase0-1.md`

- [ ] **Step 1: Add README section for harness engineering**

Include:
- why this repo uses harness-engineering controls
- where to find baseline metrics
- how docs governance runs locally and in CI

- [ ] **Step 2: Create phase adoption checklist**

Checklist categories:
- baseline metrics configured
- first snapshot captured
- AGENTS/docs map completed
- docs lints wired locally and in CI
- known gaps + owners

- [ ] **Step 3: Validate discoverability**

Run:
`rg -n "Harness Engineering|docs-governance|metrics-baseline|adoption-checklist" README.md docs/harness/adoption-checklist-phase0-1.md -S`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add README.md docs/harness/adoption-checklist-phase0-1.md
git commit -m "docs: add harness phase0-1 operator guide and checklist"
```

---

## Chunk 3: Verification + Handoff

### Task 7: Full verification before closeout

**Files:**
- Modify: none (verification only)

- [ ] **Step 1: Run verification bundle**

Run:
- `zsh -n scripts/docs/*.sh`
- `zsh scripts/docs/lint_docs_map.sh`
- `zsh scripts/docs/lint_docs_freshness.sh`
- `jq -e . docs/harness/templates/metric-snapshot-template.json >/dev/null`
- `test -f docs/records/index.md`
- `test -f docs/harness/metrics-baseline.md`

Expected: PASS

- [ ] **Step 2: Run impacted repo tests**

Run:
- `swift test --package-path Packages/VoxApplication`
- `swift test --package-path Packages/VoxPresentation`

Expected: PASS (or document pre-existing failures)

- [ ] **Step 3: Capture final change summary**

Run:
- `git status --short`
- `git diff --name-only --cached`

Expected: only docs/scripts/workflow/review-gate files related to Phase 0-1 are changed

- [ ] **Step 4: Final commit (if needed)**

```bash
git add -A
git commit -m "chore: complete harness engineering phase0-1 rollout"
```

---

## Out of Scope (Phase 0-1)

- UI automation via browser/DevTools-style runtime control
- full observability stack per worktree (temporary logs/metrics/traces lifecycle)
- architecture structural lints for package dependency direction (planned in Phase 2)
- autonomous fix loops for bug reproduction and patch validation (planned in Phase 3+)

## Risks and Mitigations

- **Risk:** Docs lint too strict and blocks normal work.
  - **Mitigation:** Start warn-first thresholds, tighten after 1-2 weeks.
- **Risk:** Baseline metrics unavailable from current tooling.
  - **Mitigation:** Record explicit null + reason, then close gaps incrementally.
- **Risk:** Duplicate plan/doc entrypoints create confusion.
  - **Mitigation:** Make `docs/records/index.md` canonical and mark legacy locations as indexed aliases.

## Execution Notes

- Use `@superpowers/verification-before-completion` before claiming rollout success.
- Use `@superpowers/requesting-code-review` after each chunk for quality/safety review.
- Keep commits small and scoped to one task for quick rollback and auditability.
