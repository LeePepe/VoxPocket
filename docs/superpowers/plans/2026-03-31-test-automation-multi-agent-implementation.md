# Multi-Agent Test Automation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved multi-agent test automation foundation: manifest-driven test orchestration, PR/Nightly GitHub workflows, module-specific suite definitions, and performance smoke/full hooks.

**Architecture:** Add a repository-local `test-executor` shell orchestrator that discovers `tests.manifest.json` suites by label and executes them with retries and artifact collection. Keep suite definitions in JSON manifests (owned by improver domains), and keep CI thin by calling executor entrypoints (`run_pr.sh`, `run_nightly.sh`). Use artifacts and a unified JSON report for downstream analysis.

**Tech Stack:** `zsh`, `jq`, GitHub Actions YAML, `swift test`, `xcodebuild`, repository shell tooling

---

## Chunk 1: Manifest-Driven Executor + CI Wiring

### Task 1: Build `test-executor` core scripts

**Files:**
- Create: `scripts/test-executor/common.sh`
- Create: `scripts/test-executor/run_by_label.sh`
- Create: `scripts/test-executor/run_pr.sh`
- Create: `scripts/test-executor/run_nightly.sh`

- [ ] **Step 1: Write failing shell checks for missing executor**

Run: `zsh scripts/test-executor/run_pr.sh`  
Expected: FAIL because executor scripts do not exist yet

- [ ] **Step 2: Implement shared helpers in `common.sh`**

Include:
- repo root resolution
- artifact/report directory bootstrap
- timeout wrapper
- suite command execution with per-suite log capture
- status emitters

- [ ] **Step 3: Implement manifest discovery and filtering in `run_by_label.sh`**

Requirements:
- discover `**/*.tests.manifest.json` under `tests/manifests/`
- filter by labels (e.g. `pr`, `nightly`)
- run suites sequentially
- apply `flakyPolicy` retry behavior
- emit `artifacts/reports/test-report.json`
- exit non-zero if any suite fails

- [ ] **Step 4: Implement entrypoints**

- `run_pr.sh` calls `run_by_label.sh pr`
- `run_nightly.sh` calls `run_by_label.sh nightly`

- [ ] **Step 5: Run syntax validation**

Run:
- `zsh -n scripts/test-executor/common.sh`
- `zsh -n scripts/test-executor/run_by_label.sh`
- `zsh -n scripts/test-executor/run_pr.sh`
- `zsh -n scripts/test-executor/run_nightly.sh`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/test-executor
git commit -m "feat: add manifest-driven test executor"
```

### Task 2: Add suite manifests for four improver domains

**Files:**
- Create: `tests/manifests/automation.pr.tests.manifest.json`
- Create: `tests/manifests/automation.nightly.tests.manifest.json`
- Create: `tests/manifests/ui.pr.tests.manifest.json`
- Create: `tests/manifests/ui.nightly.tests.manifest.json`
- Create: `tests/manifests/voice.pr.tests.manifest.json`
- Create: `tests/manifests/voice.nightly.tests.manifest.json`
- Create: `tests/manifests/performance.pr.tests.manifest.json`
- Create: `tests/manifests/performance.nightly.tests.manifest.json`

- [ ] **Step 1: Write schema-conformant manifests**

Each manifest must include:
- `suiteId`
- `owner.agent` and `owner.team`
- `entry.command`, `entry.timeoutSeconds`
- `labels`
- `dependencies`
- `flakyPolicy`
- `artifactsContract.required/optional/retentionDays`

Hard constraints to implement and validate:
- `suiteId` is globally unique across all manifest files
- `labels` contains exactly one frequency label: `pr` or `nightly`
- when `flakyPolicy.allowRetry=false`, `flakyPolicy.maxRetries` must equal `0`

- [ ] **Step 2: Validate manifests are parseable JSON**

Run:
`for f in tests/manifests/*.json; do jq -e . "$f" >/dev/null || exit 1; done`

Expected: PASS

- [ ] **Step 2.1: Validate cross-file manifest invariants**

Run:
`zsh scripts/test-executor/validate_manifests.sh`

Expected: PASS only if uniqueness/frequency/flaky invariants all hold

- [ ] **Step 3: Validate executor discovery**

Run: `zsh scripts/test-executor/run_pr.sh`  
Expected: executor finds all `pr` manifests and starts running suites (suite commands may fail in non-CI environments; discovery and orchestration must work)

- [ ] **Step 4: Commit**

```bash
git add tests/manifests
git commit -m "test: add suite manifests for automation ui voice and performance"
```

### Task 3: Add GitHub Actions PR and Nightly workflows

**Files:**
- Create: `.github/workflows/tests-pr.yml`
- Create: `.github/workflows/tests-nightly.yml`

- [ ] **Step 1: Add PR workflow**

Requirements:
- trigger on `pull_request`
- install `jq`
- checkout repo
- run `zsh scripts/test-executor/run_pr.sh`
- print `artifacts/reports/test-report.json` in a dedicated summary step (always-run)
- always upload `artifacts/`

- [ ] **Step 2: Add Nightly workflow**

Requirements:
- trigger on `schedule` + `workflow_dispatch`
- run `zsh scripts/test-executor/run_nightly.sh`
- print `artifacts/reports/test-report.json` in a dedicated summary step (always-run)
- always upload `artifacts/`

- [ ] **Step 3: Validate workflow YAML**

Run:
`rg -n "name:|on:|run: zsh scripts/test-executor/run_(pr|nightly).sh" .github/workflows/tests-*.yml -S`

Expected: PASS with both workflow files matched

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/tests-pr.yml .github/workflows/tests-nightly.yml
git commit -m "ci: add pr and nightly test automation workflows"
```

### Task 4: Add performance runner scaffold and usage docs

**Files:**
- Create: `scripts/perf/run_perf_suite.sh`
- Modify: `README.md`

- [ ] **Step 1: Implement performance suite runner**

`run_perf_suite.sh` should:
- accept one required mode parameter: `smoke|full`
- support optional `--dry-run` flag:
  - print resolved command/thresholds
  - create no xcodebuild side effects
  - exit `0`
- `smoke` mode command:
  `xcodebuild test -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -destination 'platform=macOS' -only-testing:VoxPocketUITests/VoxPocketPerformanceTests/testLaunchPerformanceSmoke`
- `full` mode command:
  `xcodebuild test -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -destination 'platform=macOS' -only-testing:VoxPocketUITests/VoxPocketPerformanceTests`
- read metrics from `artifacts/performance/raw-metrics.json` and evaluate thresholds to produce:
  - `artifacts/performance/perf-threshold-result.json`
  - `artifacts/performance/perf-threshold-summary.txt`
- when mode is `full`, compare against baseline history and additionally produce:
  - `artifacts/performance/perf-baseline-diff.json`
  - `artifacts/performance/perf-baseline-summary.txt`
- nightly baseline rule:
  - compare against median of last 14 nightly runs
  - if any core metric degrades by `> 15%`, return non-zero
- threshold rules (from spec):
  - `smoke`: startup `p95 <= 4.0s`, firstText `p95 <= 6.0s`
  - `full`: startup `p95 <= 3.0s`, firstText `p95 <= 4.5s`, fullTranscription `p95 <= 12.0s`, peakMemory `<= 1.2GB`

- [ ] **Step 2: Update README test automation section**

Document:
- manifest location
- executor entrypoints
- PR/Nightly workflow file names
- local dry-run command examples

- [ ] **Step 3: Syntax validation**

Run:
- `zsh -n scripts/perf/run_perf_suite.sh`
- `zsh scripts/perf/run_perf_suite.sh smoke --dry-run`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/perf/run_perf_suite.sh README.md
git commit -m "docs: add test executor usage and perf runner"
```

### Task 5: End-to-end verification before handoff

**Files:**
- Modify: none (verification only)

- [ ] **Step 1: Run local verification commands**

Run:
- `zsh -n scripts/test-executor/*.sh scripts/perf/run_perf_suite.sh`
- `for f in tests/manifests/*.json; do jq -e . "$f" >/dev/null || exit 1; done`
- `zsh scripts/test-executor/run_pr.sh || true`
- `test -f artifacts/reports/test-report.json`
- `jq -e '.suites | length > 0' artifacts/reports/test-report.json >/dev/null`

Expected:
- syntax and JSON checks PASS
- `run_pr.sh` produces `artifacts/reports/test-report.json`
- report contains at least one suite result object

- [ ] **Step 2: Capture final diff summary**

Run:
- `git status --short`
- `git diff --name-only HEAD~4..HEAD` (or equivalent range)

Expected: only test-executor/manifests/workflow/perf/doc files are changed

- [ ] **Step 3: Final commit (if verification-required adjustments exist)**

```bash
git add scripts/test-executor scripts/perf tests/manifests .github/workflows README.md
git commit -m "chore: finalize multi-agent test automation scaffold"
```

Plan complete and saved to `docs/superpowers/plans/2026-03-31-test-automation-multi-agent-implementation.md`. Ready to execute?
