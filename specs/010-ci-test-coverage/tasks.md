# Tasks: Required PR coverage for every VoxPocket test file

**Input**: [`spec.md`](./spec.md), [`plan.md`](./plan.md), [`research.md`](./research.md), [`data-model.md`](./data-model.md), [`contracts/test-coverage-contract.md`](./contracts/test-coverage-contract.md), [`quickstart.md`](./quickstart.md)  
**Baseline**: `ea88c649ca4faca45d2265b667cc83712dbe5a68`  
**Execution rule**: each executable task owns one repository layer or one explicit support scope. Required check names, release behavior, product code, and SPM tests remain unchanged.

## Phase 1: US1 — Root script coverage (P1)

**Goal**: every `scripts/tests` and icon test is auto-discovered by a required PR lane; packaging drift fails before release.

**Independent test**: required logs name all nine `scripts/tests` files and both icon files; a temporary Python canary is discovered without registration; the Ruby test passes against the unchanged TestFlight gate.

- [ ] T001 [US1] Implement and unit-test fail-closed sorted test-file discovery groups in `scripts/ci/run_repository_tests.py` and `scripts/ci/tests/test_repository_tests.py`
- [ ] T002 [P] [US1] Correct only the stale TestFlight gate expectation in `scripts/tests/test_testflight_packaging.rb`
- [ ] T003 [US1] Replace the six hand-registered app harness gates with the `_root support` `app-python` discovery interface in `VoxPocket/tech-context.md`
- [ ] T004 [US1] Install/reuse Fastlane Ruby and run the `packaging-ruby` discovery group in required App CI via `.github/workflows/ci.yml`

### Task metadata — US1

| ID | Owner layer or support scope / context | In-scope paths | Explicit exclusions | Contract impact | Task-local acceptance and verification | Dependencies / slice |
|---|---|---|---|---|---|---|
| T001 | `_root support`; `docs/architecture/tech-context.md` | `scripts/ci/run_repository_tests.py`; `scripts/ci/tests/test_repository_tests.py` | No `.github/**`, app sources, Xcode tests, SPM packages, or generic MY-1608 policy | Creates the discovery CLI in `contracts/test-coverage-contract.md` | Unit fixtures prove sorted path logging, direct Python-file execution, Ruby executable/env handoff, icon discovery dispatch, zero-match failure, and child-failure propagation. Run `python3 scripts/ci/tests/test_repository_tests.py`. | None; realizes US1 |
| T002 | `_root support`; `docs/architecture/tech-context.md` | `scripts/tests/test_testflight_packaging.rb` | No `.github/workflows/testflight.yml`, release scripts, or other assertions | Updates expected text only; release contract unchanged | Fastlane Ruby command passes; `git diff -- .github/workflows/testflight.yml` is empty; changed line equals current gate message. | None; realizes US1; `[P]` with T001 |
| T003 | `VoxPocketApp`; `VoxPocket/tech-context.md` | `VoxPocket/tech-context.md` gate/frontmatter and gate description only | No runner implementation, product Swift, `project.yml`, or generated Xcode project | Consumes T001's `_root support` `app-python` contract; removes hand-list seam | `scripts/verify --layer VoxPocketApp` prints/executes all eight baseline Python files under `scripts/tests`; temporary discovery canary is observed then absent from Git status. Frontmatter check passes. | T001 support/gate contract edge; realizes US1 |
| T004 | `_root support`; `docs/architecture/tech-context.md` | App-job setup/steps in `.github/workflows/ci.yml` only | No TestFlight workflow, ruleset/check rename, Xcode test step (T008), or secrets | Consumes T001 `packaging-ruby` with R-003 env | Workflow lint passes. Required App log names every `test_*.rb` match and shows Ruby packaging pass. Fastlane/Ruby failure is fatal. | T001, T002; realizes US1 |

**US1 checkpoint**: US1/AC1–AC4 and FR-001/FR-004/FR-006 have direct evidence; US1/AC5 remains the explicit post-merge Owner follow-up.

---

## Phase 2: US2 — Governance suites and local-tool classification (P1)

**Goal**: live zsh suites and manifest integrity become required policy evidence without reviving the retired dispatcher or promoting the local executor to CI authority.

**Independent test**: `scripts/verify --policy` names and passes all discovered zsh suites, test-executor syntax, all eight manifests, icon tests, Python review tests, the three preserved gate tests, and the preserved Kimi review-contract test.

- [ ] T005 [US2] Make zsh suite discovery fail-closed and replace stale orchestrator positives with D-002 retirement/current-handler assertions in `scripts/ci/tests/test_runner.sh` and `scripts/ci/tests/orchestrator_hook_tests.sh`
- [ ] T006 [US2] Replace only the two Python review-test hand calls with discovery, preserve the existing gate-test discovery and direct Kimi review-contract invocation, and add icon, zsh, executor-syntax, and manifest checks in `scripts/verify`
- [ ] T007 [P] [US2] Repair the local PR UI manifest to select the full live bundle in `tests/manifests/ui.pr.tests.manifest.json`

### Task metadata — US2

| ID | Owner layer or support scope / context | In-scope paths | Explicit exclusions | Contract impact | Task-local acceptance and verification | Dependencies / slice |
|---|---|---|---|---|---|---|
| T005 | `_root support`; `docs/architecture/tech-context.md` | `scripts/ci/tests/test_runner.sh`; `scripts/ci/tests/orchestrator_hook_tests.sh` | No retired workflow restoration; no changes to six other suite assertions; no dispatcher launcher/agent implementation changes | Zsh discovery and RB-001/D-002 replacement coverage | Runner discovers sorted `*_tests.sh`, excludes helpers/itself, prints every path, fails empty/nonzero, and passes. PR weakening section lists every replaced obsolete assertion, D-002, and replacement guard; Owner approval is mandatory. | None; realizes US2 |
| T006 | `_root support`; `docs/architecture/tech-context.md` | `scripts/verify` policy function only | No layer gates; no removal, replacement, bypass, or non-required relocation of the four existing root-test invocations; no privacy weakening, gitleaks bypass, app Xcode step, local executor wrappers, or required-check changes | Makes policy authoritative for new icon/zsh/syntax/manifest and `scripts/ci/tests/test_*.py` discovery while preserving existing required policy tests | Preserve required unittest discovery of `scripts/gates/tests/test_local_hooks.py`, `test_private_config.py`, and `test_test_weakening.py` plus direct `bash` execution of `scripts/ci/kimi-review.contract.test.sh`, with each path/test named in policy logs. Also run `zsh -n scripts/test-executor/*.sh scripts/perf/run_perf_suite.sh`; eight-manifest validation; `python3 -m unittest discover -s scripts/ci/tests -p 'test_*.py'`; T001 icons group; T005 runner; `scripts/verify --policy`; all exit 0. | T001, T005; realizes US2 and US4/AC4 |
| T007 | `_root support`; `docs/architecture/tech-context.md` | `tests/manifests/ui.pr.tests.manifest.json` command selector only | No runner semantics, retries, dependencies, nightly manifests, or Xcode source | Preserves local-only status; removes nonexistent singleton selector | `zsh scripts/test-executor/validate_manifests.sh` reports eight; manifest selects full `VoxPocketUITests`; PR body records local-only/non-authoritative disposition. | None; realizes US2; `[P]` with T005/T006 where files do not conflict |

**US2 checkpoint**: US2/AC1–AC4 and FR-001/FR-005/FR-006 have direct evidence; no test file is deleted.

---

## Phase 3: US3 — Xcode unit/UI bundles in required App CI (P1)

**Goal**: the generated full Xcode scheme test action executes in required PR CI without secrets, delivery actions, filters, or new skips.

**Independent test**: the required `App target` log and `.xcresult` name `VoxPocketTests` and `VoxPocketUITests` on the exact PR head.

- [ ] T008 [US3] Add the unfiltered full-scheme macOS Xcode test step and exact result logging to required App CI in `.github/workflows/ci.yml`
- [ ] T009 [US3] Run the CI feasibility checkpoint and, only if necessary, make deterministic test-setup repairs within `VoxPocket/project.yml`, `VoxPocket/VoxPocketTests/**`, or `VoxPocket/VoxPocketUITests/**`

### Task metadata — US3

| ID | Owner layer or support scope / context | In-scope paths | Explicit exclusions | Contract impact | Task-local acceptance and verification | Dependencies / slice |
|---|---|---|---|---|---|---|
| T008 | `_root support`; `docs/architecture/tech-context.md` | Required App-job test step in `.github/workflows/ci.yml` | No TestFlight, archive/install/upload, ruleset/check rename, credentials, `-only-testing`, `-skip-testing`, or product code | Implements Xcode CI contract; consumes generated scheme | Workflow lint passes. Draft-PR App job runs `xcodebuild test` on `platform=macOS` with CI-compatible ad-hoc signing, no filter, no Claude/Anthropic secret, and retains `.xcresult`/summary. | T004, T007; realizes US3 |
| T009 | `VoxPocketApp`; `VoxPocket/tech-context.md` | Primary deliverable is CI evidence; conditional repair scope limited to `VoxPocket/project.yml`, `VoxPocket/VoxPocketTests/**`, `VoxPocket/VoxPocketUITests/**` | No `VoxPocket/VoxPocket/**` product source, generated `.xcodeproj`, new skip/exclusion/disabled test, assertion weakening, secret injection, or release action | Confirms target-directory discovery and existing platform skips; no interface change expected | App log/`.xcresult` reports both bundles, pass/fail/skip counts and existing skip reasons. If deterministic test setup cannot pass within scope, stop with exact failing test/evidence and return to Team Lead/Planner; do not widen scope. `project.yml` remains source of truth. | T008; realizes US3 and is the explicit feasibility spike/checkpoint |

**US3 checkpoint**: US3/AC1–AC5 and FR-002/FR-004/FR-005/FR-007 are evidenced on the current PR head. Any product-code need or new weakening blocks rather than becoming an inferred task.

---

## Phase 4: US4 — Exact-head delivery evidence (P1)

**Goal**: a non-draft PR carries complete, exact-SHA evidence and Owner approval for important/test-contract paths.

**Independent test**: local SHA, pushed branch SHA, and PR `headRefOid` match; every required check is green on that SHA; all PR-template sections are complete.

- [ ] T010 [US4] Execute the full verification/evidence checklist and populate the PR from `.github/pull_request_template.md` with exact-head mappings for every authoritative row including the four preserved root-policy tests, D-002 weakening declaration, executor disposition, and `owner-review`

### Task metadata — US4

| ID | Owner layer or support scope / context | In-scope paths | Explicit exclusions | Contract impact | Task-local acceptance and verification | Dependencies / slice |
|---|---|---|---|---|---|---|
| T010 | `_root support` integration/evidence; `docs/architecture/tech-context.md`, `.github/pull_request_template.md` | PR body/evidence; no template edit expected | No merge, TestFlight dispatch, assertion change, check downgrade, or stale-SHA evidence | Finalizes PR evidence contract | Run all `quickstart.md` local commands; capture required policy log entries proving execution of `test_local_hooks.py`, `test_private_config.py`, `test_test_weakening.py`, and `kimi-review.contract.test.sh`; run `scripts/verify --policy`, `--layer VoxPocketApp`, `--all`; confirm TestFlight workflow diff is empty; bind logs to equal local/remote/PR SHA; non-draft; all required checks green; Owner approval present for D-002/CODEOWNERS changes. | T003, T006, T009; realizes US4, including US4/AC4 |

**US4 checkpoint**: US4/AC1–AC4, FR-003, and FR-008 are satisfied for one exact PR head.

## Dependencies and execution order

```text
T001 ─┬─> T003 ─────────────────────────────┐
      ├─> T004 ─> T008 ─> T009 ───────────┤
T002 ─┘                                     │
T005 ─> T006 ──────────────────────────────┤
T007 ─────────────> T008                    │
                                            v
                                           T010
```

- T002, T005, and T007 may proceed in parallel because their files do not conflict.
- T004 and T008 both edit `.github/workflows/ci.yml`; serialize them in that order.
- T001 (`_root support`) → T003 (`VoxPocketApp` gate) is a support/gate contract edge, not a cross-layer dependency.
- T009 is a layer-scoped CI checkpoint/spike. Its output is evidence plus only bounded test-target setup repairs, if required.
- T010 waits for every acceptance-bearing task and invalidates/repeats evidence after any push.

## Acceptance coverage matrix

| Acceptance | Task(s) |
|---|---|
| US1/AC1 | T002, T004 |
| US1/AC2, US1/AC3 | T001, T003, T004 |
| US1/AC4 | T001, T006 |
| US1/AC5 | T010 plus post-merge F-001 |
| US2/AC1, US2/AC2, US2/AC3 | T005, T006 |
| US2/AC4 | T006, T007, T010 |
| US3/AC1, US3/AC2, US3/AC3, US3/AC4, US3/AC5 | T008, T009 |
| US4/AC1, US4/AC2, US4/AC3 | T010 |
| US4/AC4 | T006, T010 |
| FR-001–FR-002 | T001, T003–T006, T008–T009 |
| FR-003–FR-008 | T002, T005–T010 |

Every acceptance criterion maps to a slice and every slice maps to tasks with one repository layer or explicit support scope.

## Post-merge follow-up (not an implementation task)

- **F-001 — Owner/TestFlight**: after authorized merge, report the merged SHA and ask the Owner to rerun `workflow_dispatch` for TestFlight. Record the run link and packaging-step result only after the Owner performs it. Agents do not trigger the workflow.

## Implementation notes

- Add `owner-review`; `.github/**`, `scripts/verify`, `VoxPocket/tech-context.md`, and the D-002 assertion replacement are important paths/contracts.
- Preserve the manifest executor's local-only documentation and do not use its retry output as required evidence.
- A failure exposed by new coverage is fixed in its owning layer or support scope. Any necessary product-source change is a planning gap and returns through Team Lead.
- No `--no-verify`, no test filter/skip, no TestFlight run, no generated Xcode project edit, and no secret injection.
