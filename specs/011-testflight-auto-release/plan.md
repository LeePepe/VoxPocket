# Implementation Plan: Automatic macOS TestFlight CD on merge to main

**Feature**: `011-testflight-auto-release` | **Date**: 2026-10-15 | **Spec**: [`spec.md`](./spec.md)
**Planning revision**: v6 — CD-on-merge mechanical reconciliation of accepted v5
**Baseline**: `ef1420234d2b56fddcf2a388eaabf97ec54126d4`
**Input**: MY-1765 body, Team Lead handoff, the mandatory MY-1768 prerequisite, the Lead's MY-1777 minimal-shape authority adopted by MY-1765, and the Owner's 2026-10-15 CD-on-merge decision; evidence and decisions are in [`research.md`](./research.md)

## Summary

Convert the existing macOS-only TestFlight workflow from manual-only to two guarded entry points: `push` to `main`, bound to that event's exact `github.sha`, and the retained manual dispatch. The workflow resolves the sole `testflight/macos-last-released` marker, validates marker ancestry, and obtains the exact `marker..github.sha` changed-path list for the automatic event (or `marker..frozen-main` manually). A small production classifier consumes that resolved status/path input and applies the explicit app-path/force contract. Manual `force` may bypass only an irrelevant-path skip. The existing build/upload lane runs unchanged, then a dependent least-privilege marker job advances the marker to the exact candidate only after upload and all failure-capable cleanup succeed.

The workflow uses one queued concurrency group, release-job `contents: read`, dependent marker-job `contents: write`, step-scoped build/signing secrets, and `always()` cleanup for temporary keychain and local tag state. All failure-capable cleanup completes before marker advancement; the marker push creates no new local tag, and any post-marker reporting/housekeeping is warning-only and non-failing. It does not add compare-and-swap, shadow-policy tests, PR/label lookup, Fastlane behavior, retries, rollback, cursors, per-SHA attempted/skip records, or another persistent state mechanism.

The implementation is one protected governance/release PR in `_root support`. Feature-focused verification consists of unit tests against the production relevance classifier, the two existing focused workflow/packaging contract tests adapted to the actual job topology and D-012 trigger, plus repository workflow lint; normal repository policy and exact-head gates still apply. Publication is blocked until separately accepted MY-1768 is merged. The branch must then rebase onto the exact `main` revision containing MY-1768 and regenerate every exact-head artifact and verdict. Branch-up-to-date enforcement and PR Manager App-identity merge are external delivery prerequisites. Product code, the MY-1768 implementation, Fastlane, CI/rulesets, `auto-merge.yml` removal, dependency pins, and iOS authorization remain outside scope.

## Technical context

**Languages/tooling**: GitHub Actions YAML, Bash, Python 3.11 unittest, Git
**Primary dependencies**: repository `scripts/verify`; shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`; the existing Fastlane/App Store Connect release lane at runtime
**Storage/data**: sole moving release-state tag `testflight/macos-last-released`; existing App Store Connect build counter; run-scoped logs and concise skip summary only
**Testing**: production relevance-classifier unit tests, existing focused workflow-freshness and packaging contract tests, and repository workflow lint for this feature; normal repository verification and protected exact-head checks remain unchanged
**Target platform**: Owner's self-hosted macOS ARM64 runner; macOS TestFlight only
**Project type**: macOS/iOS app repository; this change is release/governance support only
**Constraints**: exact `github.sha` for push and frozen `main` for manual dispatch; merged+accepted MY-1768 and rebase before publication; one queued concurrency group and one last-released marker; no CAS, PR-label/version-policy subsystem, per-SHA attempted/skip record, cursor, retry, rollback, or reconciliation; no new secret; Owner approval for `.github/**`; post-merge live evidence remains external
**Scale/scope**: one release workflow, one small production classifier, three existing focused test files, one release guide, one narrow canonical delivery-rule edit in `AGENTS.md`, one implementation PR, and one post-merge Outcome Check

## Constitution check — before research

| Principle / rule | Result | Plan response |
|---|---|---|
| I Immutability | PASS | The candidate SHA is frozen once. The existing marker changes only after a successful upload. |
| II Layer direction | PASS | All implementation paths resolve to `_root support`; no product-layer dependency edge is added. |
| III Concurrency safety | PASS | One app-specific concurrency group queues jobs with `cancel-in-progress: false`; no second synchronization protocol is added. |
| IV Privacy | PASS | Logs and the irrelevant-skip summary contain repository/run metadata only, never app user data. |
| V Secrets/vendor hygiene | PASS | Existing secret names are reused only on the steps that need them; values are neither logged nor persisted. |
| VI Boundary validation | PASS | Event kind/ref, candidate SHA, marker resolution/ancestry, and changed paths are validated before release work. |
| CI/release protocol | PASS WITH OWNER GATE | Exact-head evidence, full repository verification, `owner-review`, and CODEOWNER approval remain mandatory. |
| TestFlight-only / iOS boundary | PASS | Only the existing macOS lane executes; iOS remains disabled. |

No constitutional exception is requested.

## Research decisions

Full evidence and rejected alternatives are in [`research.md`](./research.md).

- **R-001**: deliver one protected `_root support` PR with exact-head evidence, `owner-review`, Owner CODEOWNER approval, and unchanged required checks.
- **R-002**: use `push: branches: [main]`, check out immutable `github.sha` with full history, and resolve manual `main` only once. Required PR CI, branch-up-to-date enforcement, and PR Manager App-identity merge remain external prerequisites.
- **R-003**: put exact `marker..candidate` app-path classification in a small production Python module and unit-test that module directly.
- **R-004**: retain one last-released marker, make candidate/marker equality a hard skip, accept an absent marker only as explicit bootstrap, and fail closed on an invalid or non-ancestor marker.
- **R-005**: limit manual `force` to relevance; it cannot override trust, marker equality/validity, signing, upload, or platform boundaries.
- **R-006**: keep the existing macOS build/upload lane, project-version behavior, and App Store Connect `latest + 1` counter unchanged; MY-1765 adds no Fastlane output or version-policy behavior.
- **R-007**: serialize evaluation/upload/marker movement with one queued concurrency group; do not add CAS, a cursor, per-SHA records, or another synchronization/state protocol.
- **R-008**: keep the release job at `contents: read`, grant `contents: write` only to the dependent marker job, keep build/signing secrets step-scoped, and run `always()` cleanup for temporary keychain and local tag state.
- **R-009**: verify the production classifier directly, adapt the existing workflow-freshness and packaging contract tests to the CD-on-merge/job-boundary contract, and retain repository workflow lint; add no new test path or shadow-policy implementation.
- **R-010**: treat merged+accepted MY-1768 as a publication prerequisite; rebase onto its exact containing `main` revision and invalidate/re-run all exact-head evidence rather than duplicating its signing changes.
- **R-011**: enforce the existing AppleUITesting full-SHA pin in the release checkout and verify checkout equality before build work; do not change the pin.
- **R-012**: include a narrow `AGENTS.md` delivery-rule reconciliation so the canonical repository rule matches D-001/D-012 while manual fallback, protected Owner approval, and iOS authorization remain unchanged.
- **R-013**: reconcile the implementation boundary to the published six-path PR plus the clean unpublished packaging-test repair, for exactly seven paths; preserve cumulative implementation-review history and do not treat the Owner's mechanical trigger revision as a budget reset.

## Design and interfaces

### Trigger and trust boundary

The workflow registers `push: branches: [main]`. Automatic candidate selection and checkout use exactly `github.sha` with `fetch-depth: 0`, and checked-out `HEAD` must equal that SHA before secret-bearing work. Manual dispatch remains macOS-only; it resolves current `main` and freezes its SHA once. Required PR CI against the up-to-date merge candidate and PR Manager App-identity merge are external prerequisites; the workflow does not poll CI, call merge APIs, or add token permissions for them.

### Relevance-classifier boundary

The classifier contract is [`contracts/testflight-release-contract.md`](./contracts/testflight-release-contract.md). It accepts the frozen candidate, resolved sole-marker status, the exact `git diff --name-only marker..candidate` paths when that status is a valid ancestor, and the manual-force value, then returns release or skip with a stable reason or rejects invalid marker state. It performs no GitHub API, Git resolution/diff, signing, build, upload, tag mutation, or persistence.

An existing marker must resolve and be an ancestor of the candidate before its diff is trusted. Candidate equality with the marker always skips. An absent marker is an explicit bootstrap release. For an existing valid marker, at least one exact app-path match releases; manual force may bypass only the no-match result. Invalid or non-ancestor marker state fails closed in the workflow before the existing build lane.

### Existing build/upload boundary

The existing macOS lane and inputs remain unchanged, including project marketing-version authority, App Store Connect `latest + 1` build numbering, package/upload behavior, runner labels, secrets, repaired MY-1768 signing/profile contract, and disabled iOS lane. The release workflow enforces the existing AppleUITesting pin with `ref: e6be2fcdf83341a9f3000a4cc489237655461a07` and a checked-out-HEAD equality check before build work; this changes no dependency revision. MY-1765 neither edits Fastlane nor creates a second release implementation.

### Marker, cleanup, and failure boundary

One workflow-level concurrency group queues evaluation, upload, cleanup, and marker handling and never cancels a running upload. The release job has `contents: read`. After a successful upload, all failure-capable `always()` cleanup and action post-steps complete. Cleanup failure fails the release job and prevents its dependent marker job from starting. Only that dependent job has `contents: write`; it pushes the exact candidate directly to the remote `testflight/macos-last-released` ref without creating a new local tag, and that marker write is the last failure-capable state transition. Any post-marker reporting/housekeeping is expressly best-effort/non-failing and emits a warning if it cannot complete. Any earlier failure or skip leaves the remote marker unchanged.

The workflow emits ordinary step logs and a concise reason summary for an irrelevant skip. It creates no CAS boundary, attempted/skip tag, cursor, reconciliation job, or rich persistent outcome model. Failure stops the run without automatic retry, rollback, alternate SHA, or fallback. If upload succeeds but marker movement fails, the run fails and surfaces that non-transactional ambiguity for human handling; it does not invent a second state mechanism.

## Implementation slices

### Slice US1 — Exact main-push trigger

Add the automatic `main` push trigger, exact `github.sha` checkout with full history, trigger-run trace, and retained manual branch. This proves that the exact merged SHA enters the automatic release path; required PR CI/up-to-date enforcement and App-identity merge stay external.

### Slice US2 — Production relevance classifier

First implement and unit-test the small pure classifier. Then make the workflow resolve marker status, equality/ancestry, and exact `marker..candidate` changed paths before passing those run-scoped inputs and relevance-only force to the classifier. Skips do not sign, build, upload, or move the marker.

### Slice US3 — Existing release lane and post-upload marker

Keep the current build/sign/upload lane unchanged, including version/counter/signing/iOS behavior. Enforce the existing AppleUITesting SHA in its checkout. Add only its guarded invocation, the release-read/marker-write permission split, successful-upload and successful-pre-marker-cleanup marker movement, one queued concurrency group, step-scoped secrets, ordered `always()` cleanup, ordinary run logs, and the irrelevant-skip reason summary. Narrowly reconcile the canonical TestFlight delivery rule in `AGENTS.md`, and update only the existing focused freshness/packaging assertions affected by trigger or job topology. US3/AC2, US3/AC3, and FR-007 are retained solely as superseded-history IDs and create no implementation task.

### Slice US4 — Exact-head protected delivery and live outcome

After MY-1768 merges with accepted manual TestFlight evidence, rebase onto the exact containing `main` revision. Any conflict or source change returns to the affected US1–US3 slice; a clean rebase still invalidates every earlier manifest, local result, review, and CI result. Regenerate the exact-head evidence, obtain the protected-path approvals, and hand the PR through the normal delivery flow. A separate post-merge Outcome Check records the first eligible live upload; fixtures cannot satisfy US4/AC4.

## Verification strategy

Commands and expected evidence are in [`quickstart.md`](./quickstart.md).

Fresh implementation evidence must include:

1. focused Python unit tests against the production classifier for exact path matching, mixed/irrelevant diffs, bootstrap, equality, invalid/non-ancestor handling, and relevance-only force;
2. the existing Python workflow-freshness and Ruby packaging contract tests updated for `push`/`github.sha`, manual force, least-privilege jobs, cleanup, and terminal marker behavior;
3. repository workflow lint proving the YAML parses and obeys the repository's workflow policy;
4. normal `scripts/verify --policy`, `scripts/verify`, and `scripts/verify --all` success with the repository-required Python 3.11+ on `PATH`, without adding a feature-specific shadow-policy suite;
5. MY-1768 merged revision plus accepted manual-release URL/build evidence and proof that the final MY-1765 head descends from the exact containing `main` revision;
6. after that rebase, completed PR template, `owner-review`, Owner CODEOWNER approval, and all required checks on one exact `headRefOid`, with branch-up-to-date enforcement and PR Manager App-identity merge available externally;
7. a separate post-merge Outcome Check with triggering push SHA, release run URL, TestFlight identity, and last-released marker at that SHA.

No new Ruby test path, static workflow shadow suite, local archive, signing, upload, app launch, or `xcodebuild` is part of local verification. The existing packaging test is an in-scope compatibility assertion, not new release behavior.

## Acceptance traceability

| Acceptance IDs | Slice | Contract / evidence |
|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, FR-001, FR-002 | US1 | push admission, exact `github.sha` checkout, trigger-run trace, focused contract tests, workflow lint |
| US2/AC1, US2/AC2, US2/AC3, US2/AC4, US2/AC5, FR-003, FR-004, FR-005 | US2 | production-classifier unit tests, marker/ancestry boundary, skip reason |
| US3/AC1, US3/AC4, US3/AC5, FR-006, FR-008, FR-009, FR-010, FR-011 | US3 | unchanged lane, queued job, least-privilege/step-scoped secrets, cleanup, post-upload marker, MY-1768 prerequisite |
| US3/AC2, US3/AC3, FR-007 | superseded history | stable IDs remain documented but authorize no implementation or verification work |
| US4/AC1, US4/AC2, US4/AC3, US4/AC4, FR-012 | US4 | focused local verification, exact-head PR evidence, Owner approval, post-merge outcome |

All 18 acceptance criteria and all 12 functional requirements retain an explicit disposition. Every executable implementation task maps back to one primary slice in `tasks.md`.

## Project structure and owned paths

```text
specs/011-testflight-auto-release/                 # planning only (_root support)
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/testflight-release-contract.md
├── checklists/requirements.md
└── tasks.md

.github/workflows/testflight.yml                   # minimal workflow integration; protected _root support
scripts/ci/testflight_relevance.py                  # production classifier; _root support
scripts/tests/test_testflight_schedule.py           # focused classifier unit tests; _root support
scripts/tests/test_testflight_freshness.py          # existing focused workflow-contract test; _root support
scripts/tests/test_testflight_packaging.rb          # existing packaging/job-boundary contract test; _root support
docs/testflight-release.md                          # direct operator guide subordinate to AGENTS.md; _root support
AGENTS.md                                           # review date + narrow canonical TestFlight delivery-rule reconciliation; protected _root support
```

Explicitly out of MY-1765 implementation scope: `fastlane/Fastfile`, all test paths other than the three named above, every `AGENTS.md` rule except the narrow TestFlight delivery wording, `docs/local-cicd.md`, `.github/workflows/ci.yml`, `.github/workflows/auto-merge.yml`, `scripts/verify`, `VoxPocket/project.yml`, all `Packages/**` product sources, other `VoxPocket/**` product sources/resources, `VoxPocketWidget/**`, rulesets, CODEOWNERS, secrets, dependency-pin changes, and MY-1768's profile/signing repair paths/tests. The final base nevertheless must contain the separately reviewed and merged MY-1768 changes.

**Structure decision**: preserve the existing workflow-to-Fastlane seam. Add only one small classifier beside its focused tests and adapt the two existing contract-test paths; no new workflow, test path, product module, dependency edge, secret, permission, or persistent store.

## Dependency graph

```text
T001 classifier + focused unit tests
  -> T002 minimal workflow + direct operator guide + canonical rule
  -> T005 publication (also requires merged+accepted MY-1768)
  -> T006 post-merge Outcome Check
```

- T001 defines executable relevance behavior in production code and focused unit tests.
- T002 wires that classifier into the minimal workflow, enforces the existing AppleUITesting pin, preserves the existing lane, updates the two existing focused contract tests and direct operator guide, and narrowly reconciles the canonical `AGENTS.md` delivery rule.
- T003 and T004 are superseded, non-executable historical task IDs; they authorize no Fastlane, label/version-policy, broad-documentation, or shadow-suite work.
- T005 is blocked until MY-1768 is merged and accepted. The branch then rebases onto its exact containing `main`; any conflict or source adjustment loops back to T001/T002. Even a clean rebase invalidates and repeats all manifests, local/review/CI evidence before publication through Fullstack → AI Reviewer → PR Manager.
- T006 is a no-code post-merge Outcome Check/wakeup that records the external release result after T005 merges.

## Constitution check — after design

PASS with no exception. The design stays in `_root support`, preserves product layers/privacy/secrets/iOS boundaries, uses one queued concurrency group, validates inputs before release work, and retains the repository's exact-head/Owner gates without adding a heavier policy or state mechanism.

## Risks and escalation conditions

| Risk | Mitigation / escalation |
|---|---|
| Marker is absent, unresolved, or non-ancestor | Absence is explicit bootstrap; unresolved/corrupt/non-ancestor state fails closed before release work. |
| Candidate equals the marker | Hard skip, including manual force; do not sign, build, upload, or move the marker. |
| Upload succeeds but marker push is rejected or unconfirmed | A determinately rejected write leaves the marker unchanged; an unconfirmed remote result is the sole external ambiguity. Fail the run, surface ordinary logs with release/run/SHA evidence, and escalate without CAS, retry, reconciliation, rollback, alternate state, or fallback. |
| Temporary signing/tag state remains after failure | Run all failure-capable `always()` cleanup before marker advancement; cleanup failure blocks the marker. Push the candidate directly to the remote marker ref without a new local tag; post-marker reporting/housekeeping is warning-only/non-failing. |
| Workflow gains broader token or secret access | Keep release-job permission exactly `contents: read` and marker-job permission exactly `contents: write`; keep existing build/signing secrets on only the steps that need them. Any broader permission is out of scope. |
| Merge push would not trigger Actions or might land untested | Require external branch-up-to-date enforcement and PR Manager App-identity merge before T005 ships. `auto-merge.yml` removal and ruleset work stay in separate Lead-owned changes; do not absorb them into PR #101. |
| Existing build/version behavior appears to require change | Stop and return to Team Lead/Owner. MY-1777 requires the lane and ASC counter to remain unchanged. |
| Live TestFlight cannot be proven before merge | Keep US4/AC4 as post-merge outcome evidence; never mark it passed from local/PR tests. |
| MY-1768 is unmerged/unaccepted or absent from final ancestry | Block T005. Do not duplicate its signing repair; after merge, rebase to the exact containing `main` revision and regenerate all evidence. |
| MY-1768 rebase conflicts with an owned implementation path | Return to T001/T002, resolve within the seven owned paths, and obtain a new exact-head review; T005 does not absorb source repair. |

## Complexity tracking

No constitutional violation or new architecture complexity requires an exception. This revision preserves v5's removal of label/version-policy, Fastlane-change, shadow-policy, broad-documentation, rich-state, and CAS proposals while mechanically replacing the obsolete `workflow_run` trigger, reconciling the actual seven-path implementation surface, and retaining the canonical delivery rule required by D-001/D-012.
