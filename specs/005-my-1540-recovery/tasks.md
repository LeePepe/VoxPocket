# Tasks: MY-1540 RepoInfra Recovery and Logging Delivery

**Input**: Design documents from `specs/005-my-1540-recovery/`

**Prerequisites**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/recovery-evidence.md](./contracts/recovery-evidence.md), [quickstart.md](./quickstart.md)

**Organization**: Every user-story phase is a vertical outcome. Every executable task owns exactly one declared layer/surface. The graph is intentionally sequential; there are no `[P]` tasks.

## Format: `[ID] [Story] Description with exact path`

- RepoInfra is an operational/control-plane scope, not a new Swift package layer.
- VoxInfrastructure benchmark tasks use `Packages/VoxInfrastructure/tech-context.md` and its test command.
- Root-coordinator tasks alone may touch `/Users/tianpli/Development/VoxPocket` or `/Applications/VoxPocket.app`.

## Phase 1: Readiness Foundation

**Purpose**: Pin authoritative runtime and external-candidate identity before any execution.

- [ ] T001 Capture current Dev Team role/runtime/daemon mappings and the external PR #35 adoption baseline in the format of `specs/005-my-1540-recovery/contracts/recovery-evidence.md`, verifying the Team Lead-provisioned isolated `delivery_work_dir`, `delivery_repo_url`, `delivery_branch`, and `delivery_base_sha` metadata for MY-1540.

### T001 metadata

| Field | Value |
|---|---|
| Owning layer | RepoInfra / Multica control plane |
| Context | `specs/005-my-1540-recovery/plan.md`; `specs/005-my-1540-recovery/contracts/recovery-evidence.md` §§1,5 |
| In scope | Current-Mac daemon `019fd055-0738-723e-a556-762fc863b720`; Codex runtime `ab653716-b90e-40f1-b6ff-5095f818a1f8`; Copilot runtime `05eda9df-e582-43e1-b8e0-3c16f847522d`; MY-1540 metadata; PR #35 live base/head |
| Excluded | Runtime rebinding; legacy daemon `019e2a6c-e1d4-737a-afca-e945ec0c8137`; implementation; primary checkout |
| Interface/contract | `Runtime Ownership Record` and `External PR #35 Adoption` preamble |
| Acceptance | Five Dev Team roles map to the two online current-Mac runtimes, zero map to the legacy daemon, and the isolated delivery workspace metadata matches its Git state and PR #35 |
| Exact verification | `multica runtime list --output json`; `multica agent get` for Team Lead/Planner/Reviewer/Fullstack/PR Manager; `multica issue get cba19180-e28c-46ce-afb2-af26a22528da --output json`; `git -C <delivery_work_dir> status --short --branch`; `git -C <delivery_work_dir> rev-parse HEAD`; `gh pr view 35 --repo LeePepe/VoxPocket --json headRefOid,baseRefOid,state` |
| Dependencies | None; blocks T002 and T007 |

---

## Phase 2: User Story 1 — Recover the Current-Mac Review Runner (Priority: P1)

**Goal**: Produce a falsifiable cause, apply only the selected reversible repair, and prove the review path fails fast and recovers without weakening the gate.

**Independent Test**: A redacted service-context evidence bundle covers all four hypotheses; an isolated outage fails closed within 120 seconds; recovery succeeds through the same interface; the exact repair digest/commit receives independent PASS.

- [ ] T002 [US1] Diagnose the runner/review path read-only across `/Users/tianpli/actions-runner/`, `/Users/tianpli/Library/LaunchAgents/actions.runner.LeePepe-VoxPocket.macmini-local.plist`, `/Users/tianpli/.codex-review/`, `.github/workflows/codex-review-target.yml`, and `scripts/ci/codex-review.sh`, producing the §2 diagnosis handoff without secret values.
- [ ] T003 [US1] Implement only T002's selected RepoInfra repair with timestamped backups: host-only under `/Users/tianpli/Library/LaunchAgents/actions.runner.LeePepe-VoxPocket.macmini-local.plist` or `/Users/tianpli/.codex-review/`, or tracked only in `.github/workflows/codex-review-target.yml`, `scripts/ci/codex-review.sh`, `scripts/ci/tests/test_codex_review_preflight.sh`, and `scripts/ci/tests/test_runner.sh`.
- [ ] T004 [US1] Validate isolated failure/recovery, rollback, actual `codex exec`, read-only/never-approve sandbox, exact PR-head equality, preserved `codex-review-target` name, and exact-digest/revision independent review using the selected host test adapter or tracked `scripts/ci/tests/test_codex_review_preflight.sh` plus the §3 handoff; if tracked files changed, merge the separate reviewed repair PR to `main` before T007.

### US1 task metadata

| ID | Owning layer | In scope | Explicit exclusions | Interface/contract | Task-local acceptance | Exact verification | Depends on |
|---|---|---|---|---|---|---|---|
| T002 | RepoInfra / runner diagnostics | Named current-Mac runner, LaunchAgent, isolated Codex home, trusted workflow/script | No edits; no environment-value/config-content output; no other runners; no global network | `Diagnosis Handoff` | Lifecycle, proxy inheritance, provider connectivity/auth, and startup dependency each have supported/rejected/inconclusive evidence; one falsifiable cause and repair target, or owner blocker | Redacted service-context runner state; bounded TCP/TLS and authenticated-path outcomes; compare GitHub run `34474957893`; `gh pr checks 35 --repo LeePepe/VoxPocket --required` | T001 |
| T003 | RepoInfra / selected repair | Only the T002-selected subset of the six listed host/tracked paths | PR #35 logging files; `Packages/**`; LokiKit; ruleset/check rename/removal; paused legacy review workflow; global proxy; other runners | `RepairCandidate` | Backups/checksums precede host changes; tracked changes add focused failure diagnostics/tests; actual Codex/read-only/exact-head/fail-closed behavior preserved | Host diff + SHA-256; or focused test and repo gates; `git diff --name-only` stays inside allowlist | T002 |
| T004 | RepoInfra integration/review | Repair evidence, isolated test adapter/process, exact host digest or Git SHA, repair PR if tracked | No synthetic green status; no third blind rerun; no self-review; no direct `main` write | `Repair and Recovery Handoff` | Explicit failure in ≤120 seconds, same interface recovers, rollback is verified, actual Codex execution/read-only sandbox/exact-head match/check-name preservation each has an evidence reference, AI Reviewer passes exact digest/SHA; tracked repair is merged into trusted `main` | Failure/recovery transcript with redaction; compare expected/reviewed head; inspect run/config evidence for `codex exec`, `sandbox_mode=read-only`, `approval_policy=never`, and `codex-review-target`; repo gates and repair-PR merge proof when applicable | T003 |

**Checkpoint**: Current-Mac runner repair is independently approved and available from the trusted execution source.

---

## Phase 3: User Story 2 — Bootstrap the Existing Supervisor (Priority: P2)

**Goal**: Make the existing NAS-bound observer run with a supported model configuration, then enable only its existing schedule.

**Independent Test**: One catalog-selected probe succeeds within the observer's hard scope before trigger `52310b59-fd61-4cf7-ae14-523ae55d2a26` is enabled; no other agent/autopilot/schedule changes.

- [ ] T005 [US2] Inspect the supported model/effort/service-tier catalog for NAS runtime `a06e54f0-65cf-46ea-96de-97da512438cf` and stage one explicit compatible configuration on observer `efc285c0-5c91-4055-80ba-e64b9d6419f9`, preserving its prior agent state and leaving trigger `52310b59-fd61-4cf7-ae14-523ae55d2a26` disabled.
- [ ] T006 [US2] Independently review the exact observer configuration digest, rehearse restoration/reapplication of its prior configuration while the trigger is disabled, execute one authorized probe of autopilot `d67e7307-d0ef-40c4-a597-fd48d73cda48`, verify observe/dispatch/bounded-rerun/report-only behavior, then enable the existing `*/10 * * * *` trigger and record the §4 handoff.

### US2 task metadata

| ID | Owning layer | In scope | Explicit exclusions | Interface/contract | Task-local acceptance | Exact verification | Depends on |
|---|---|---|---|---|---|---|---|
| T005 | RepoInfra / Multica observer config | Existing observer agent and NAS runtime catalog; prior blank/default model state | No shared agents, Dev Team bindings, runtime update, new credentials, new autopilot/trigger, or trial-and-error writes | `SupervisorBootstrap` candidate | One catalog-supported tuple is selected; prior state/rollback recorded; trigger remains disabled | `multica agent get efc285c0-5c91-4055-80ba-e64b9d6419f9 --output json`; authoritative runtime-catalog evidence; `multica autopilot get d67e7307-d0ef-40c4-a597-fd48d73cda48 --output json` | T004 |
| T006 | RepoInfra / Multica observer verification | Exact T005 agent config, prior/selected config digests, rollback rehearsal, one probe run, existing schedule trigger | No implementation/config edits by observer; no second probe; no schedule until PASS | `Existing-Autopilot Bootstrap Handoff` | Independent PASS matches selected-config digest; prior config restores and selected config reapplies; probe succeeds and stays in scope; only existing trigger enabled | Review evidence ID/verdict/digest; rollback timestamp/result; `multica autopilot runs d67e7307-d0ef-40c4-a597-fd48d73cda48 --output json`; `multica autopilot get ... --output json`; verify trigger ID/cron/timezone/status and no added trigger | T005 |

**Checkpoint**: Existing task-specific supervisor is operational without replacing it or moving Dev Team roles.

---

## Phase 4: User Story 3 — Adopt and Ship Existing PR #35 (Priority: P3)

**Goal**: Bring the external logging candidate into the controlled delivery flow and merge it only after exact-head required review.

**Independent Test**: Adoption metadata matches the isolated checkout and live PR; all eight required checks pass on one current head; GitHub confirms auto-squash merge and remote `main` containment.

- [ ] T007 [US3] Finalize the external PR adoption record for `https://github.com/LeePepe/VoxPocket/pull/35` against MY-1540 and the isolated `delivery_work_dir`, refreshing it onto the repaired trusted `main` when T004 produced a tracked repair and recapturing exact base/head SHAs.
- [ ] T008 [US3] Supervise PR #35 through a real exact-head `codex-review-target` PASS, all contexts in `scripts/rulesets/main-protection.json`, existing auto-squash merge, and remote-main containment, then write the §5 shipping handoff.

### US3 task metadata

| ID | Owning layer | In scope | Explicit exclusions | Interface/contract | Task-local acceptance | Exact verification | Depends on |
|---|---|---|---|---|---|---|---|
| T007 | RepoInfra / delivery intake | MY-1540 metadata, isolated checkout, PR #35 live base/head/scope/evidence | No feature recreation; no author-based exclusion; no primary checkout; no stale SHA | `ExternalPRAdoption` | Issue/repo/workspace/branch/base/head/scope/evidence agree byte-for-byte; any repaired base is incorporated normally | `multica issue get ...`; `git status --short --branch`; `git rev-parse HEAD`; `gh pr view 35 --json headRefOid,baseRefOid,state` | T001, T004, T006 |
| T008 | RepoInfra / protected GitHub delivery | PR #35, `scripts/rulesets/main-protection.json`, required check/run evidence | Kimi as substitute; synthetic status; gate change; force-push; admin/direct merge | `ShippingRecord` | Eight required checks succeed on current head; auto-merge remains enabled; GitHub reports MERGED and remote `main` contains merge SHA | `gh pr checks 35 --repo LeePepe/VoxPocket --required`; `gh pr view 35 ...`; `git ls-remote ... refs/heads/main`; compare head/check/merge SHAs | T007 |

**Checkpoint**: Existing logging implementation is merged; no replacement PR was created for it.

---

## Phase 5: User Story 4 — Benchmark Production Transcription Adapters (Priority: P4)

**Goal**: Ship a separate privacy-safe test harness and produce case-specific measurements from the approved fixture.

**Independent Test**: A Packages-only reviewed PR adds the harness; the current-Mac live run produces exactly one cold and five warm serial measurements per supported group/mode, a protected full report, and a sanitized numeric summary with no private-field leakage.

- [ ] T009 [US4] Provision the task-local sibling dependency with `multica repo checkout https://github.com/LeePepe/LokiKit --ref eff9c1712cd648ed0717e41183ad8bd7bf39cbea` so `<benchmark_delivery_work_dir>/Packages/VoxInfrastructure/../../../LokiKit` resolves to `<task-root>/LokiKit`, then record its absolute path, origin URL, exact HEAD, and clean status without editing LokiKit.
- [ ] T010 [US4] Register the dedicated `PrivateTranscriptionBenchmarkTests` target in `Packages/VoxInfrastructure/Package.swift`; add minimal testability seams in `Packages/VoxInfrastructure/Sources/TranscriptionKit/DefaultAppleSpeechRequestFactory.swift` and `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift`; and prove them in `Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/ProductionAdapterSeamTests.swift` with `SilentBenchmarkLogger.swift`.
- [ ] T011 [US4] Implement `Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/ApprovedOwnerBenchmarkTests.swift`, `BenchmarkAudioFixture.swift`, `ProductionRecognitionAdapters.swift`, `BenchmarkMetricsAndScoring.swift`, and `PrivateBenchmarkReportWriter.swift` for protected input/output, production adapters, serial cold/warm plans, timing/scoring, hybrid stages, no-op telemetry, and sanitized failures.
- [ ] T012 [US4] Verify the Packages-only benchmark diff with `swift build --package-path Packages/VoxInfrastructure` and `swift test --package-path Packages/VoxInfrastructure`, obtain exact-revision independent PASS, and merge the separate benchmark PR through all normal gates.
- [ ] T013 [US4] Under root-coordinator coordination, run `ApprovedOwnerBenchmarkTests/testOwnerFixture` on current-Mac daemon `019fd055-0738-723e-a556-762fc863b720` using only `/Users/tianpli/Library/Containers/com.leepepe.voxpocket/Data/Library/Application Support/VoxPocket/benchmarks/owner-20260910/manifest.json`, retaining full results under its protected `results/<UTC>-<git-sha>/` and publishing the §6 summary with current-Mac/NAS-isolation proof, Apple route fields, and reproducible cold/warm state.

### US4 task metadata

| ID | Owning layer | In scope | Explicit exclusions | Interface/contract | Task-local acceptance | Exact verification | Depends on |
|---|---|---|---|---|---|---|---|
| T009 | RepoInfra / dependency workspace | Task-local sibling `<task-root>/LokiKit` resolved by VoxInfrastructure's `../../../LokiKit` dependency | No LokiKit source edits, branch changes, commits, cleanup, pushes, global cache changes, or primary checkout | `BenchmarkDependencyCheckout` | Absolute resolved path, authoritative origin URL, exact published SHA, and clean status are recorded; `source_edits=false` | `git -C <task-root>/LokiKit remote get-url origin`; `git -C <task-root>/LokiKit rev-parse HEAD`; `git -C <task-root>/LokiKit status --porcelain`; resolve `Packages/VoxInfrastructure/../../../LokiKit` | T008; blocks T010 and T012 |
| T010 | VoxInfrastructure / TranscriptionKit Service | `Package.swift`, two named source files, `ProductionAdapterSeamTests.swift`, `SilentBenchmarkLogger.swift` | No coordinator-wide refactor; no app/UI/default model; no other package; no LokiKit source edits | Internal/testable production adapter seam | Apple request policy is shared; actual Apple route stays `unknown` unless proved; identical file/buffer input is possible; WhisperKit benchmark logs are off | `swift test --package-path Packages/VoxInfrastructure --filter PrivateTranscriptionBenchmarkTests` | T009 |
| T011 | VoxInfrastructure / TranscriptionKit test harness | Five named harness files in the dedicated test target | No fixture/text in Git/stdout/Loki; no speaker replay; no new backend/credential/endpoint; no fallback relabeling | `BenchmarkRun` and `BenchmarkReport` | Manifest/path/symlink/mode validation; one cold + five warm serial plan; complete metrics; scoring-only reference; silent logs; private report + sanitized summary | Focused synthetic fixtures only; scan captured stdout/summary for forbidden fields; assert stable error codes rather than strings | T010 |
| T012 | VoxInfrastructure integration/review | Exact benchmark commit/PR, package verification, and T009 dependency evidence | No `xcodebuild` for Packages-only diff; no self-review; no bypass; no shared cache deletion | Exact-revision benchmark handoff | Pinned LokiKit path/remote/SHA/clean state remains true; build and full package tests pass; independent PASS matches pushed PR head; normal checks merge the separate PR | Re-run T009 evidence; `git diff --name-only origin/main...HEAD` all under `Packages/`; `swift build ...`; `swift test ...`; compare local SHA, remote branch SHA, PR `headRefOid`; verify MERGED | T011 |
| T013 | VoxInfrastructure / private live test | Exact manifest root/results on current Mac; existing Azure service; base/turbo caches; recorded process/engine/order state | NAS access/copy; Git/issue attachments; global cache reset; reference as model input; p95; default change | §6 `Benchmark Handoff`; `data-model.md#coldwarm-benchmark-semantics` | Current-Mac daemon/runtime proven and NAS read/copy counts are zero; each group/mode has a fresh-process cold run then five same-process warm runs; Apple availability and actual route are separate; full timing/scoring/privacy fields complete | Opt-in filtered test command; verify process generations/order/cache fields, route fields, report permissions/containment, numeric schema count, sanitized audit reference, and independent summary review | T012 |

**Checkpoint**: Benchmark harness and PR #35 are merged; private benchmark evidence is complete and case-bounded.

---

## Phase 6: User Story 5 — Validate, Archive, and Install Final Main (Priority: P5)

**Goal**: Root coordinator validates the candidate without replacing the old app, builds final `main`, then performs a reversible authorized installation.

**Independent Test**: Candidate safe-marker logging passes while `/Applications/VoxPocket.app` remains recoverable; final source/dependency SHAs are recorded; a new validated archive is installed after a user-state preflight; exactly one instance runs.

- [ ] T014 [US5] In `/Users/tianpli/Development/VoxPocket`, preserve unrelated untracked paths, synchronize final remote `main`, record PR #35/benchmark/LokiKit SHAs and dirty state, build a new `build/local/VoxPocket-<UTC>-<sha>.xcarchive`, run the private-config bundle guard, and validate the archive app's safe startup log before changing `/Applications/VoxPocket.app`.
- [ ] T015 [US5] After confirming no active recording or unsaved text, capture the installed app's bundle/version/build/code-directory identity, create a timestamped backup of `/Applications/VoxPocket.app`, rehearse and timestamp a same-filesystem restore with matching identity while retaining the backup, gracefully quit, install the validated archive app, reopen exactly one instance, and verify sandbox/preferences/private config preservation.

### US5 task metadata

| ID | Owning layer | In scope | Explicit exclusions | Interface/contract | Task-local acceptance | Exact verification | Depends on |
|---|---|---|---|---|---|---|---|
| T014 | Root-coordinator local delivery | Primary checkout, published LokiKit sibling, new archive, archive app candidate, local Loki safe marker | No cleanup of `.playwright-mcp/`, `docs/research/`, `output/`; no old archive reuse; no install yet; no TestFlight | §7 `source`, `candidate_validation`, `archive` | Local/remote main exact; both merge SHAs present; new archive exists; bundle guard passes; candidate alone emits safe marker while installed app remains backed by its unchanged path | Git SHA/status; repository archive command; archive app existence; private-config guard; bounded Loki marker query | T008, T012, T013 |
| T015 | Root-coordinator local delivery | Installed app, timestamped backup, graceful process lifecycle, existing sandbox/preferences/config | No action while recording/unsaved text; no data/config deletion; no second instance; no backup deletion | §7 `pre_install`, `install`, `rollback` | Preflight confirmed; backup identity matches the old app; restore rehearsal method/timestamp/result are recorded and pass; installed bits come from T014 archive; exactly one instance; user state preserved | Bundle ID/version/build/code-directory hash before/backup/restore; process count; app launch; same-filesystem temporary restore or controlled full-swap rehearsal; backup retained | T014 |

**Checkpoint**: Final merged-main app is installed safely and reversible.

---

## Phase 7: User Story 6 — Real-App Acceptance and Closeout (Priority: P6)

**Goal**: Prove installed-app log delivery/privacy and return one complete evidence package before stopping the temporary supervisor.

**Independent Test**: Installed app startup plus harmless window action yields expected log records in a five-minute window, Grafana is ready, forbidden content count is zero, and the existing observer schedule is disabled only after Team Lead validates all evidence.

- [ ] T016 [US6] Exercise startup plus one harmless window operation in `/Applications/VoxPocket.app`, query separate allowlisted startup and window markers within the same `{app="VoxPocket",stream="log"}` acceptance window, inspect all returned records for forbidden content categories, verify Grafana `/d/voxpocket-logs`, and complete §7 `post_install_acceptance` without recording voice.
- [ ] T017 [US6] Deliver the complete `specs/005-my-1540-recovery/contracts/recovery-evidence.md` record to Team Lead, then after acceptance disable trigger `52310b59-fd61-4cf7-ae14-523ae55d2a26` and record `disable_after_delivery: complete` without deleting the autopilot.

### US6 task metadata

| ID | Owning layer | In scope | Explicit exclusions | Interface/contract | Task-local acceptance | Exact verification | Depends on |
|---|---|---|---|---|---|---|---|
| T016 | Root-coordinator acceptance | Installed app, loopback Loki/Grafana, startup/window action, five-minute records | No microphone/voice; no smoke-harness substitution; no private text in evidence | `TelemetryAcceptance` | Startup marker count ≥1 and window-action marker count ≥1 are independently recorded inside the same query window; dashboard ready; forbidden-content count zero | Separate marker queries/counts/timestamps and evidence refs; exact UTC bounds; Grafana health/dashboard response; process/app identity | T015 |
| T017 | RepoInfra / delivery closeout | Complete sanitized handoff and existing schedule state | No `done` before Team Lead acceptance; no autopilot deletion; no new trigger | Full recovery evidence contract | Every mandatory field is present and exact; Team Lead accepts delivery; existing schedule disabled | Re-read issue evidence; `multica autopilot get d67e7307-d0ef-40c4-a597-fd48d73cda48 --output json`; trigger ID disabled | T016 |

---

## Dependencies & Execution Order

```text
T001
 └─> T002 -> T003 -> T004 -> T005 -> T006 -> T007 -> T008
                                                       |
                                                       v
                       T009 -> T010 -> T011 -> T012 -> T013
                                                       |
                                                       v
                              T014 -> T015 -> T016 -> T017
```

The authoritative edge list is:

- T001 → T002, T007
- T002 → T003 → T004 → T005 → T006
- T004 + T006 + T001 → T007 → T008
- T008 → T009 → T010 → T011 → T012 → T013
- T008 + T012 + T013 → T014 → T015 → T016 → T017

There are no parallel markers because the owner requested ordered delivery and shared current-Mac/root-coordinator surfaces must not overlap.

## Acceptance Coverage

| Spec coverage | Slice/tasks |
|---|---|
| FR-001–FR-007, SC-001–SC-002 | US1 / T002–T004 |
| FR-021, SC-008 | Foundation / T001 |
| FR-022, SC-009 | US2 / T005–T006 |
| FR-008–FR-011, FR-023, SC-003 | US3 / T007–T008 |
| FR-024–FR-032, SC-010–SC-011 | US4 / T009–T013 |
| FR-012–FR-016, SC-004, SC-007 | US5 / T014–T015 |
| FR-017–FR-020, SC-005–SC-007 | US6 / T016–T017 |

## Implementation Strategy

1. Finish the runner and existing-supervisor control plane before handing PR #35 to PR Manager.
2. Ship PR #35 normally; then implement and ship the separate Packages-only benchmark harness.
3. Run the private benchmark and candidate log validation on the current Mac.
4. Root coordinator builds final `main`, backs up and replaces the app, then proves installed-app telemetry/privacy.
5. Team Lead accepts the complete evidence; only then disable the task-specific schedule.

## Notes

- All implementation children remain unassigned until this exact planning revision receives AI Reviewer PASS and Team Lead schedules them.
- Host changes are reviewed by exact digest/diff; repository changes by pushed commit SHA and PR head.
- A new endpoint/credential/provider/model for the review gate, an unavailable benchmark provider, or an uncertain app user-state check is reported as a blocker rather than guessed around.
