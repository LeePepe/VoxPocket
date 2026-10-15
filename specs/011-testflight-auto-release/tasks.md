# Tasks: Automatic macOS TestFlight CD on merge to main

**Input**: [`spec.md`](./spec.md), [`plan.md`](./plan.md), [`research.md`](./research.md), [`data-model.md`](./data-model.md), [`contracts/testflight-release-contract.md`](./contracts/testflight-release-contract.md), [`quickstart.md`](./quickstart.md)
**Planning revision**: v6 — CD-on-merge mechanical reconciliation of accepted v5
**Baseline**: `ef1420234d2b56fddcf2a388eaabf97ec54126d4`
**Execution rule**: one protected `_root support` PR, published only after separately accepted MY-1768 merges and the branch rebases onto its exact containing `main` revision. Product layers, CI required checks, rulesets, secrets, dependency pins, iOS authorization, and MY-1768 signing implementation remain outside MY-1765 scope.

## Owned implementation paths

MY-1765 may change exactly these seven repository paths, reconciling PR #101 and the preserved unpublished repair:

1. `.github/workflows/testflight.yml`
2. `scripts/ci/testflight_relevance.py`
3. `scripts/tests/test_testflight_schedule.py`
4. `scripts/tests/test_testflight_freshness.py`
5. `scripts/tests/test_testflight_packaging.rb`
6. `docs/testflight-release.md`
7. `AGENTS.md` (only `Last-Reviewed` plus the canonical TestFlight delivery-rule wording)

Every other test path, every other `AGENTS.md` rule, `docs/local-cicd.md`, `fastlane/Fastfile`, product/project files, `.github/workflows/ci.yml`, `.github/workflows/auto-merge.yml`, rulesets, dependency-pin changes, secrets, and MY-1768 code are explicitly excluded.

## Phase 1: US2 — Production relevance classifier (P1)

**Goal**: one small production classifier decides bootstrap, exact `marker..candidate` path relevance, same-marker skip, force relevance bypass, and invalid-marker failure.

**Independent test**: focused unit tests exercise the production classifier directly with resolved-status/path input fixtures; no Git invocation or static workflow shadow-policy suite is introduced.

- [ ] T001 [US2] Add the production relevance classifier and replace obsolete static schedule assertions with focused classifier unit tests in `scripts/ci/testflight_relevance.py` and `scripts/tests/test_testflight_schedule.py`

### Task metadata — Phase 1

| ID | Owner / context | In-scope paths | Explicit exclusions | Contract impact | Task-local acceptance and verification | Dependencies / slice |
|---|---|---|---|---|---|---|
| T001 | `_root support`; `docs/architecture/tech-context.md` | `scripts/ci/testflight_relevance.py`; `scripts/tests/test_testflight_schedule.py` | No workflow, docs, Git/GitHub API, build/sign/upload, persisted state, cursor, retry, CAS helper, policy-shadow parser, Fastlane/Ruby/product/project change, or MY-1768 repair | Implements the real relevance decision used by both triggers and replaces the classifier-facing RB-002/RB-004 obsolete assertions | Direct input fixtures exercise absent-marker bootstrap; marker equal to candidate; valid-ancestor and invalid/non-ancestor marker status; exact relevant/irrelevant/mixed path lists across `Packages/**`, `VoxPocket/**`, `VoxPocketWidget/**`, `fastlane/**`, `.github/workflows/testflight.yml`, and `scripts/ci/fetch-external-deps.sh`; accumulated relevant changes; malformed path input failing closed; and manual force bypassing relevance only. Tests prove no per-SHA attempted/skip record, cursor, reconciliation, alternate SHA, rollback, or retry. Run `python3 scripts/tests/test_testflight_schedule.py`. | None; establishes the executable classifier contract for US2 |

## Phase 2: US1/US2/US3 — Minimal workflow, focused contract tests, and direct guide (P1)

**Goal**: an eligible merge push to `main` releases its exact `github.sha` when the classifier admits it, through the unchanged macOS build/upload lane.

**Independent test**: T001, the two existing focused workflow/packaging contract tests, and repository workflow lint validate the minimal workflow and dependent marker job; no additional feature-specific harness is added.

- [ ] T002 [US1] Wire the minimal release workflow, focused contract tests, direct operator guide, and narrow canonical delivery-rule reconciliation in `.github/workflows/testflight.yml`, `scripts/tests/test_testflight_freshness.py`, `scripts/tests/test_testflight_packaging.rb`, `docs/testflight-release.md`, and `AGENTS.md`

### Task metadata — Phase 2

| ID | Owner / context | In-scope paths | Explicit exclusions | Contract impact | Task-local acceptance and verification | Dependencies / slice |
|---|---|---|---|---|---|---|
| T002 | protected `_root support`; `docs/architecture/tech-context.md`, `AGENTS.md` delivery rules | `.github/workflows/testflight.yml`; `scripts/tests/test_testflight_freshness.py`; `scripts/tests/test_testflight_packaging.rb`; `docs/testflight-release.md`; `Last-Reviewed` plus narrow TestFlight delivery-rule wording in `AGENTS.md` | No `.github/workflows/ci.yml`, `.github/workflows/auto-merge.yml`, ruleset/required-check change, new test path, new secret, product/project/version edit, Fastlane behavior change, other `AGENTS.md` rule or `docs/local-cicd.md` edit, MY-1768 repair, dependency-pin value change, PR-label/API lookup, semantic-version policy engine, per-SHA state/cursor, CAS job/helper, retry/rollback, or iOS enablement | Implements D-009/D-012's minimal trigger, candidate, relevance, existing lane, marker, cleanup, permission, concurrency, test, and operator contract; reconciles D-001/D-010 with the canonical repository rule, enforces D-011, and records D-013's actual implementation surface | Automatic entry is `push: branches: [main]`; candidate and checkout are exactly `github.sha` with `fetch-depth: 0` and checked-out equality. The AppleUITesting checkout sets `ref: e6be2fcdf83341a9f3000a4cc489237655461a07` and verifies checked-out `HEAD` equality before build work. Manual entry freezes current `main`; `force` bypasses relevance only. The workflow resolves marker/equality/ancestry, obtains the exact `marker..candidate` path list, and passes those inputs to T001, with documented absent-marker bootstrap and fail-closed invalid/non-ancestor behavior. It retains `[self-hosted, macOS, ARM64]`, the existing macOS lane, App Store Connect latest+1 counter, step-scoped build/signing secrets, and disabled iOS boundary. Release-job permission is exactly `contents: read`; only the dependent marker job has `contents: write`; one workflow-level queued concurrency group has `cancel-in-progress: false`. Upload and all failure-capable `always()` cleanup/action post-steps precede sole-marker advancement; failure blocks the marker job. The marker step pushes the exact candidate directly to the remote tag ref without creating new local-tag state and is the final failure-capable state transition; post-marker reporting/housekeeping is warning-only/non-failing. The existing freshness/packaging contract tests replace obsolete trigger assumptions and preserve force, permission, cleanup, authenticated marker, and terminal-marker coverage. The narrow `AGENTS.md` edit retains manual fallback, protected Owner approval, and separate iOS authorization. Run `python3 scripts/tests/test_testflight_schedule.py`, `python3 scripts/tests/test_testflight_freshness.py`, the Brew Ruby/Fastlane invocation of `scripts/tests/test_testflight_packaging.rb`, and `scripts/verify --policy`; all pass, and the direct operator guide/canonical rule match the workflow. | T001; realizes the active US1/US2/US3 contract |

## Phase 3: Superseded v3 work (non-executable)

The Lead's D-009 minimal shape supersedes these identifiers without renumbering them:

- T003 — **SUPERSEDED / NON-EXECUTABLE**: no Fastlane output interface or Ruby packaging-test expansion.
- T004 — **SUPERSEDED / NON-EXECUTABLE**: no rich outcome-state integration, broad guide/AGENTS rewrite, label/API/version-policy subsystem, or additional workflow harness.

T003 and T004 own no path, have no dependency edge, and must not be scheduled. They retain traceability for superseded US3/AC2, US3/AC3, and FR-007 only.

## Phase 4: US4 — Exact-head protected delivery (P1)

**Goal**: after MY-1768 is both merged and accepted, publish and ship one reviewed protected PR with every artifact and check bound to one immutable head.

**Independent test**: MY-1768 evidence, implementation evidence, independent review, approvals, and required checks are bound to one PR SHA.

- [ ] T005 [US4] After merged+accepted MY-1768, rebase, regenerate all evidence, then publish and ship the exact-head protected PR through Fullstack → AI Reviewer → PR Manager

### Task metadata — Phase 4

| ID | Owner / context | In-scope paths | Explicit exclusions | Contract impact | Task-local acceptance and verification | Dependencies / slice |
|---|---|---|---|---|---|---|
| T005 | `_root support` dependency/rebase/implementation-review/shipping handoff; `AGENTS.md`, PR template, MY-1768 evidence | MY-1768 merge SHA + accepted manual TestFlight run URL/build; exact post-dependency `main` base; ancestry proof; seven-path frozen candidate manifest; regenerated verification logs; PR body; reviews/checks; external branch-up-to-date/App-identity readiness | No MY-1768 implementation, profile/project repair, `auto-merge.yml`/ruleset change, merge bypass, admin merge, local upload, fabricated live result, retry of ambiguous upload, or new implementation path | Finalizes mandatory signing dependency and protected exact-head publication contract | First prove MY-1768 merged and accepted; rebase onto the exact `main` revision containing it and prove ancestry. Any conflict or source adjustment returns to T001–T002. On the resulting head rerun classifier tests, focused freshness/packaging tests, workflow lint, and all normal repository gates; freeze the exact seven-path candidate; obtain independent approval before publication; prove local/remote/PR SHA equality; disclose RB-001–RB-005 and all superseded behavior; obtain `owner-review`, Owner CODEOWNER approval, green required checks, external branch-up-to-date readiness, and PR Manager App-identity normal merge. Preserve the cumulative implementation-review history; the D-012 revision does not reset or add review budget. Any rebase/new push invalidates SHA-bound evidence. | T002 **and merged+accepted MY-1768**; realizes US3/AC4 and US4/AC1–AC3 |

## Phase 5: US4 — Post-merge Outcome Check (P1)

**Goal**: independently record the first eligible automatic macOS upload after the implementation merge.

**Independent test**: one merged SHA is equal across the triggering `main` push, checkout/release evidence, and last-released marker, with exactly one ASC upload identity.

- [ ] T006 [US4] Create/execute a no-code Outcome Check or condition wakeup for the first eligible automatic TestFlight outcome on MY-1765

### Task metadata — Phase 5

| ID | Owner / context | In-scope paths | Explicit exclusions | Contract impact | Task-local acceptance and verification | Dependencies / slice |
|---|---|---|---|---|---|---|
| T006 | Team Lead-owned Outcome Check after merge; MY-1765 and GitHub/ASC release evidence | No repository file; issue evidence only | No implementation, PR mutation, upload rerun, marker repair, fabricated outcome, or agent dispatch before condition holds | Proves the external outcome without conflating it with implementation acceptance | Capture merged/released SHA; triggering `main` push/TestFlight run URL; uploaded outcome; marketing/build identity; `testflight/macos-last-released` resolving to that SHA; and one upload only. External required-PR-CI/up-to-date/App-identity evidence may be recorded as a prerequisite but is not source authorization. If the first merge is ineligible, wait for the next eligible merge. Ambiguous upload/marker outcomes escalate and remain incomplete; there is no automatic retry. | T005 merged; realizes US4/AC4 only |

## Dependencies and execution order

```text
T001 ──> T002 ──> T005 ──> T006
                    ▲
MY-1768 merged + accepted evidence
```

- T003 and T004 are superseded traceability records, not executable graph nodes.
- T005 is not schedulable from T002 alone: MY-1768 must also be merged with accepted manual-release evidence.
- Rebase onto the exact `main` revision containing MY-1768 and prove ancestry. Any conflict or source change loops back to T001–T002; even a clean rebase invalidates and repeats exact-head local/review/check evidence. Shipping additionally requires external branch-up-to-date enforcement and PR Manager App-identity merge; neither is implemented by this task graph.
- T006 cannot run before T005 merges and changes no repository file; use a condition wakeup/Outcome Check rather than keeping an implementation agent alive.

## Acceptance coverage matrix

| Acceptance | Task(s) |
|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4 | T002, T005 |
| US2/AC1, US2/AC2, US2/AC3, US2/AC4, US2/AC5 | T001, T002, T005 |
| US3/AC1 | T002, T005 |
| US3/AC2–AC3 | T003/T004 retained as superseded, non-executable traceability under D-009 |
| US3/AC4 | T002 preserves the non-signing contract; completion requires merged+accepted MY-1768, then T005 rebase/reverification |
| US3/AC5 | T001, T002, T005 |
| US4/AC1, US4/AC2, US4/AC3 | T001, T002, T005 |
| US4/AC4 | T006 post-merge only |
| FR-001, FR-002, FR-003, FR-004, FR-005 | T001, T002 |
| FR-006 | T002 |
| FR-007 | T003/T004 retained as superseded, non-executable traceability under D-009 |
| FR-008, FR-009, FR-010, FR-011 | T001, T002 |
| FR-012 | T005, T006 |

All 18 stable acceptance criteria and all 12 stable functional-requirement IDs remain mapped. Every executable task has one layer/support owner, exact paths or evidence surface, exclusions, dependencies, and verification.

## Implementation notes

- The seven owned implementation paths are exhaustive; `AGENTS.md` is limited to `Last-Reviewed` plus the canonical TestFlight delivery-rule reconciliation.
- Add `owner-review`; `.github/**` requires Owner CODEOWNER approval.
- In the PR's Removed or weakened tests or policy section, disclose RB-001–RB-005, including removal of unimplemented v3 label/API/Fastlane/rich-state proposals, replacement of obsolete static policy assertions with focused production-classifier tests, adaptation of the existing freshness/packaging contract tests, and replacement of the floating AppleUITesting checkout with the existing full-SHA pin.
- Treat an invalid/non-ancestor marker, classifier/Git failure, build-counter failure, and ambiguous upload/marker state as blockers, not fallbacks.
- Treat unmerged/unaccepted MY-1768 or missing ancestry as a T005 blocker. Do not copy its signing repair into MY-1765; after its merge, rebase and regenerate exact-head evidence.
- Do not use `--no-verify`, local `xcodebuild`, local signing/archive/upload, iOS lane, new secrets, a second release workflow, CAS coordination, or automatic retry.
