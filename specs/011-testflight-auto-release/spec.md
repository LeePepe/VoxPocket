# Feature Specification: Automatic macOS TestFlight CD on merge to main

**Feature**: `011-testflight-auto-release`
**Created**: 2026-10-15
**Status**: Draft for independent spec/plan review
**Planning revision**: v6 — CD-on-merge mechanical reconciliation of accepted v5
**Input**: MY-1765; Team Lead handoff `01a13cc9-8329-79d1-9be2-2bf7aa0dfa81`; MY-1768 prerequisite authority `01a13b42-e51d-732c-b0c6-9eeb3d2ab7ff`; MY-1777 minimal-shape authority `01a13cc2-c043-7989-b6ae-da334ba1d333`; MY-1765 adoption authority `01a13cc2-e49a-7db2-9792-630c36ea6206`; Owner CD-on-merge decision `01a13ee3-fce1-7432-9144-64cd9077e5a3`; Team Lead reconciliation `01a13ee7-76ad-71ad-a669-1bb2985ed17c`
**Baseline**: `LeePepe/VoxPocket` at `ef1420234d2b56fddcf2a388eaabf97ec54126d4`

Stable IDs are append-only. Plan, tasks, verification, and review findings MUST cite them exactly. Text marked superseded is historical traceability, not implementation authority.

## Decisions and authority

- **D-001 — Owner release rule (MY-1765, 2026-10-14; trigger refined by D-012)**: after a merge to `main`, the app publishes to TestFlight automatically on the Owner's existing self-hosted Mac. Per-upload Owner confirmation is retired. D-012 makes the merge push, rather than a post-merge CI completion, the release trigger because required PR CI and branch-up-to-date enforcement are external merge prerequisites.
- **D-002 — Platform boundary**: this version automates macOS TestFlight only. The disabled iOS lane and the requirement for separate Owner authorization remain unchanged.
- **D-003 — superseded v5 trigger, retained for history**: v5 used a completed successful `workflow_run` of the repository workflow named `CI` on `main`. D-012 replaces only that automatic trigger/candidate contract with `push` to `main` and exact `github.sha`; `workflow_dispatch` with `force` remains available for manual operation.
- **D-004 — Protected change**: `.github/**` is CODEOWNERS-protected. The implementation PR requires `owner-review` and Owner CODEOWNER approval; an approved plan does not replace execution approval or protected-path approval.
- **D-005 — superseded v3 proposal (not implementation authority)**: v3 proposed `release:minor` label lookup, first-parent PR association, workflow-enforced semantic-version transitions, and related Fastlane/output work. MY-1777 authority D-009 removes that unimplemented subsystem from MY-1765. `VoxPocket/project.yml` remains unchanged and supplies the marketing version already consumed by the existing lane.
- **D-006 — superseded v2 proposal (not implementation authority)**: v2 proposed a per-SHA attempted tag. Owner decision D-008 rejected that additional persistent state before implementation; no attempted tag, per-SHA skip record, or cursor may be added.
- **D-007 — mandatory signing prerequisite (Owner comment `01a13b42-e51d-732c-b0c6-9eeb3d2ab7ff`)**: MY-1768 must merge first and satisfy its signing acceptance before MY-1765 may enter publication. The MY-1765 branch must then rebase onto the exact `main` revision containing the MY-1768 merge, prove ancestry, and regenerate all exact-head evidence. MY-1765 does not absorb the signing repair; any conflict or source change returns to the affected implementation tasks before publication.
- **D-008 — Owner minimal release state (comment `01a13b86-1f25-76e8-90d7-fd07fba704e8`)**: the workflow has one queued concurrency group and exactly one persistent release-state marker, `testflight/macos-last-released`. Relevance is evaluated over `marker..candidate`; manual `force` bypasses only an irrelevant-path skip. Indeterminate or failed conditions stop the current run, leave the marker unchanged when failure occurs before the marker attempt or the write is determinately rejected, and create no retry, rollback, reconciliation, alternate SHA, per-SHA attempted/skip record, or cursor. A transport-indeterminate remote marker push is the sole case where state is not asserted, per US3/AC5.
- **D-009 — active MY-1777 minimal-shape authority, with trigger/permission details reconciled by D-012/D-013 (Owner/Lead comments `01a13cc2-c043-7989-b6ae-da334ba1d333` and `01a13cc2-e49a-7db2-9792-630c36ea6206`)**: retain exact-candidate relevance over `git diff --name-only marker..candidate`, the existing macOS build/upload lane, marker advancement only after successful upload and cleanup, one concurrency group with `cancel-in-progress: false`, step-scoped build/signing secrets, and no CAS boundary, shadow-policy suite, rich outcome state machine, label/API/version-range subsystem, automatic retry, or heavier mechanism. D-012 supersedes only the `workflow_run`/`head_sha` trigger detail. D-013 records the already-approved least-privilege two-job permission boundary and focused contract-test adaptations.
- **D-010 — canonical delivery-rule reconciliation**: D-001/D-012 supersede the baseline manual-per-upload wording in `AGENTS.md`. The implementation updates only that delivery rule to name automatic CD for the exact `main` push SHA, retain manual dispatch as fallback, retain protected-path Owner approval, and retain separate iOS authorization. No other repository rule changes.
- **D-011 — existing AppleUITesting pin enforcement**: the release workflow must consume the repository-authoritative AppleUITesting revision `e6be2fcdf83341a9f3000a4cc489237655461a07`, already used by CI, rather than the baseline release checkout's moving default branch. This is enforcement of the existing pin, not a pin-value change.
- **D-012 — Owner CD-on-merge decision (2026-10-15, comments `01a13ee3-fce1-7432-9144-64cd9077e5a3` and `01a13ee7-76ad-71ad-a669-1bb2985ed17c`)**: automatic entry is `push: branches: [main]`; the automatic candidate and checkout are exactly `github.sha`. Manual `workflow_dispatch` and its documented frozen-`main` fallback remain. Branch-up-to-date enforcement and PR Manager App-identity merges are external delivery prerequisites. Removal of `auto-merge.yml` belongs to separate Lead PRs and is not part of PR #101.
- **D-013 — accepted implementation-surface reconciliation**: PR #101 at published head `e2f290c7a8ba9f8535d1c2c2f86e11f6f420981d` contains the v5 five paths plus `scripts/tests/test_testflight_freshness.py`; preserved clean unpublished repair `8ebfc3c473bc88a86d93b5155d8b3b1fa1d5b9a1` additionally changes only `scripts/tests/test_testflight_packaging.rb`. The exact implementation boundary is therefore seven paths. Preserve the accepted release-job `contents: read` and dependent marker-job `contents: write` split. This mechanical decision does not reset or add to the cumulative implementation-review budget.

## Actors and outcome

- **App user / tester**: receives the next eligible, CI-verified macOS build in TestFlight without a per-release Owner action.
- **Maintainer**: can trace a release or skip to the exact triggering `main` push run and SHA through ordinary Actions logs; an irrelevant-path skip also has a concise reason summary.
- **Owner**: retains manual `force` dispatch and protected-path approval while no longer confirming each upload.

## Existing behavior

At the baseline SHA:

| Surface | Existing behavior |
|---|---|
| Trigger | `.github/workflows/testflight.yml` registers only `workflow_dispatch`; its job guard rejects non-manual events, so a merge push to `main` never publishes. |
| Source revision | The workflow checks out moving `main`; it is not bound to the triggering push's immutable `github.sha`. |
| Release gate | The gate compares checked-out `HEAD` with `testflight/macos-last-released`. `force=true` bypasses inequality, allowing the same SHA to upload again. There is no app-path relevance check. |
| Runner / concurrency | Release runs on `[self-hosted, macOS, ARM64]` with concurrency group `testflight` and `cancel-in-progress: false`. |
| Build / signing | The existing macOS lane queries the latest macOS TestFlight build across versions, uses `latest + 1`, builds, and uploads. iOS is hard-disabled. Existing ASC/keychain secrets are consumed. The release workflow checks out `LeePepe/AppleUITesting` without a `ref`, so it can differ from CI's pinned revision. The baseline's hard-coded signing/profile contract caused manual run `38598643529` to fail; MY-1768 owns that repair and its accepted live evidence. |
| Marker | After successful upload, the workflow force-moves the sole marker `testflight/macos-last-released` to the released SHA. There is no attempted/skip record or cursor. |
| Cleanup / reporting | The baseline workflow has no explicit temporary keychain/local-tag cleanup step. Actions retains logs, but the workflow has no automatic-trigger trace or app-relevance reason. |
| Tests | `scripts/tests/test_testflight_schedule.py` statically asserts manual-only triggering and moving-`main` checkout. The separate Ruby packaging tests protect the existing lane and disabled-iOS behavior. |
| In-flight implementation evidence | PR #101 publishes six paths at `e2f290c7a8ba9f8535d1c2c2f86e11f6f420981d`; the preserved unpublished repair at `8ebfc3c473bc88a86d93b5155d8b3b1fa1d5b9a1` adds only the packaging-test adaptation. Neither revision implements D-012 yet. |

## User scenarios and acceptance criteria

### US1 — Merged main SHA automatically enters release (P1)

As a tester, I want each eligible merge push to `main` to release that exact revision after required PR CI has already verified what will land, so distribution is traceable and does not depend on another Owner action.

**Independent test**: workflow lint validates the event/guard/ref shape, and post-merge evidence shows the trigger payload, checkout, upload, and marker use the same SHA.

- **US1/AC1**: The workflow registers `push: branches: [main]` and retains `workflow_dispatch` with boolean `force` defaulting to `false` and the macOS-only platform choice.
- **US1/AC2**: Automatic release proceeds only for the `main` push event and uses exactly `${{ github.sha }}` as its candidate. Required PR CI, branch-up-to-date enforcement, and PR Manager App-identity merge are external delivery prerequisites, not reimplemented as workflow polling or permissions.
- **US1/AC3**: Automatic checkout uses `${{ github.sha }}` with full history and verifies checked-out `HEAD` equals it. Manual dispatch resolves `main` once and records that exact candidate; later movement of `main` cannot change the run's SHA. The release checkout of `LeePepe/AppleUITesting` sets `ref: e6be2fcdf83341a9f3000a4cc489237655461a07` and verifies its checked-out `HEAD` equals that full SHA before build work, matching the dependency revision used by repository verification.
- **US1/AC4**: Ordinary Actions logs identify the triggering push run and exact candidate. The implementation does not rename or edit `.github/workflows/ci.yml`, any required check, any ruleset, or `auto-merge.yml`.

### US2 — Only app-relevant, unreleased revisions upload (P1)

As a maintainer, I want docs/spec/CI-only merges to skip TestFlight and already-released SHAs to stop, while manual force can release an unreleased SHA deliberately.

**Independent test**: focused unit tests of `scripts/ci/testflight_relevance.py` exercise path matching and decision inputs without building or contacting App Store Connect.

- **US2/AC1**: App-relevant paths are exactly `Packages/**`, `VoxPocket/**`, `VoxPocketWidget/**`, `fastlane/**`, `.github/workflows/testflight.yml`, and `scripts/ci/fetch-external-deps.sh`.
- **US2/AC2**: When `git diff --name-only marker..candidate` contains no US2/AC1 path, the workflow skips before signing/build/upload and reports `no app-relevant changes since testflight/macos-last-released` without logging secret or user content.
- **US2/AC3**: When the marker is absent, the candidate is an explicit bootstrap release because no trusted baseline exists. When present, the marker object must resolve and be an ancestor of the candidate before the exact two-dot diff is trusted; invalid, missing, or non-ancestor state fails closed.
- **US2/AC4**: A candidate equal to `testflight/macos-last-released` always skips as `already released`, including `force=true`. No additional per-SHA attempted/skip record or cursor is consulted or created.
- **US2/AC5**: On manual dispatch, `force=true` bypasses only the relevance result for an unreleased SHA. It does not bypass macOS-only policy, exact-SHA selection, marker equality, secrets/signing validation, or fail-closed behavior.

### US3 — Build and failure behavior stay deterministic (P1)

As the Owner, I want the existing macOS release lane preserved and failures to leave the sole release marker trustworthy.

**Independent test**: classifier unit tests and workflow lint cover the new eligibility seam; the unchanged existing lane remains covered by existing repository gates and is proven live only after merge.

- **US3/AC1**: The workflow calls the existing macOS build/upload lane unchanged. Its App Store Connect latest-macOS-build plus one counter and project-supplied marketing version remain authoritative; MY-1765 adds no Fastlane output, label, API, or version-transition logic.
- **US3/AC2 — superseded history, not implementation authority**: v3 required first-parent mainline PR association and validation of unlabeled version transitions. D-009 removes that unimplemented requirement; no such lookup or validation is built.
- **US3/AC3 — superseded history, not implementation authority**: v3 required `release:minor` label processing and semantic-minor transition checks. D-009 removes that unimplemented requirement; no label provisioning, `pull-requests: read`, or project-version mutation is part of MY-1765.
- **US3/AC4**: Release stays on `[self-hosted, macOS, ARM64]` in one app-specific concurrency group with `cancel-in-progress: false`. Existing ASC/keychain secret names, the repaired in-run profile contract accepted and merged by MY-1768, the macOS-only lane, and disabled iOS lane remain unchanged. MY-1765 cannot publish against a base lacking the MY-1768 merge and accepted successful manual-run evidence.
- **US3/AC5**: Upload runs before marker advancement. All failure-capable `always()` cleanup completes before marker advancement; on an otherwise successful release, cleanup failure fails the job and blocks the marker write. The marker write is the last failure-capable state transition and pushes the exact candidate directly to the remote marker ref without creating a new local tag. Any post-marker reporting/housekeeping is explicitly best-effort/non-failing and logs a warning on failure. Any eligibility, signing, build, upload, or pre-marker-cleanup failure fails the job and proves the remote marker was not attempted; a determinately rejected marker write also leaves it unchanged. A marker push whose remote result cannot be confirmed is the sole reported external ambiguity and does not claim the marker stayed unchanged. Ordinary logs report the reachable outcome and exact candidate, while an irrelevant-path skip also writes the concise reason required by US2/AC2. No automatic retry, rollback, reconciliation, fallback SHA, CAS helper, second marker, or rich state machine is added.

### US4 — Protected delivery and post-merge proof are exact (P1)

As the Owner, I want implementation and release evidence bound to immutable SHAs so the protected workflow change and first automatic upload are auditable.

**Independent test**: the implementation PR records focused test/lint and normal repository-gate evidence on one head SHA, then the next eligible merged `main` SHA supplies the external upload proof.

- **US4/AC1**: Before publication, MY-1768 is merged with accepted manual TestFlight URL/build evidence; MY-1765 rebases onto its exact containing `main` revision and proves ancestry. On the rebased head, production-classifier unit tests, the existing focused workflow-freshness and packaging contract tests, and repository workflow lint pass, together with the normal unmodified repository verification gates. No new test path, shadow-policy, CAS, or packaging behavior is added; heavy app build remains CI-only.
- **US4/AC2**: The PR is non-draft, uses `owner-review`, receives Owner CODEOWNER approval, and all repository-required checks are green on the same `headRefOid` named in test evidence.
- **US4/AC3**: The PR body declares RB-001 through RB-005, the replacement—not deletion—of obsolete static scheduling assertions, the focused freshness/packaging contract-test adaptations, release-job `contents: read` plus dependent marker-job `contents: write`, step-scoped build/signing secrets, no iOS authorization, and the seven-path implementation boundary below. The `AGENTS.md` change is limited to its review date plus reconciliation of the canonical TestFlight delivery rule with D-001/D-010/D-012.
- **US4/AC4**: After merge, the resulting eligible `main` push causes one macOS TestFlight upload. MY-1765 receives the release run URL, triggering push SHA, marketing version, and monotonically increasing build number. This external outcome is not claimed from pre-merge tests.

## Functional requirements

- **FR-001**: Automatic entry MUST be `push` to `main` and MUST bind candidate and checkout to its exact `github.sha`.
- **FR-002**: Manual `workflow_dispatch` with `force` MUST remain available with the narrowed bypass in US2/AC5.
- **FR-003**: Eligibility MUST compare the exact candidate to `testflight/macos-last-released` and evaluate the US2/AC1 path set over exact `marker..candidate`, failing closed on indeterminate state.
- **FR-004**: A candidate equal to the marker MUST never upload again, including under force. That marker MUST be the only persistent release state; the workflow MUST NOT create or consult attempted/skip records, cursors, CAS metadata, or any second state mechanism.
- **FR-005**: Release jobs MUST serialize in one VoxPocket macOS concurrency group and MUST NOT cancel an in-progress upload.
- **FR-006**: The existing macOS lane and its App Store Connect latest-build plus one contract MUST remain unchanged.
- **FR-007 — superseded history, not implementation authority**: v3 required label-driven marketing-version validation over the marker-to-candidate mainline range. D-009 removes that unimplemented subsystem; MY-1765 MUST NOT implement it.
- **FR-008**: Existing secret names, the separately accepted MY-1768 signing contract, marker name, macOS lane, AppleUITesting pin value, and iOS prohibition MUST be preserved; the release workflow MUST set and verify the existing AppleUITesting full-SHA revision, and build/signing secrets MUST be scoped only to the steps that consume them.
- **FR-009**: Ordinary logs MUST identify the trigger/candidate and reachable release, skip, or failure result without secret or user content; the irrelevant-path skip MUST also write its concise reason. No all-outcome summary state machine, rich outcome model, or persistent evidence store is added.
- **FR-010**: No automatic retry, rollback, fallback revision, reconciliation, CAS boundary, ruleset change, or required-check change is allowed.
- **FR-011**: Deterministic verification MUST comprise focused unit tests of the production relevance classifier, the existing workflow-freshness and packaging contract tests updated for CD-on-merge, and repository workflow lint; obsolete manual-only/`workflow_run` assertions are replaced, and no parallel shadow-policy suite or new test path is added.
- **FR-012**: Protected implementation and release evidence MUST be exact-SHA evidence as defined by US4.

## Implementation boundary

The owned implementation is exactly seven paths, reconciling the published PR and preserved repair:

1. `.github/workflows/testflight.yml` — minimal trigger, exact-SHA, relevance, existing-lane, marker, permission, concurrency, and cleanup orchestration.
2. `scripts/ci/testflight_relevance.py` — small production classifier for the exact app-path policy.
3. `scripts/tests/test_testflight_schedule.py` — focused unit tests of that production classifier, replacing obsolete static manual-only assertions; workflow lint remains the repository's existing shared-ci policy check.
4. `scripts/tests/test_testflight_freshness.py` — existing focused workflow-contract test, adapted from `workflow_run` source identity to `push`/`github.sha` while preserving least privilege, cleanup, and terminal marker checks.
5. `scripts/tests/test_testflight_packaging.rb` — existing packaging contract test, including the clean unpublished compatibility repair for force input and the dependent marker job; update only assumptions affected by D-012.
6. `docs/testflight-release.md` — direct operator guide subordinate to the canonical `AGENTS.md` rule.
7. `AGENTS.md` — update `Last-Reviewed` and narrowly reconcile the canonical TestFlight delivery rule with automatic exact-`main`-push CD while retaining manual fallback, protected Owner approval, and the iOS boundary.

Explicitly excluded are `fastlane/Fastfile`, all other test paths, all other `AGENTS.md` rules, `docs/local-cicd.md`, product/project files, `.github/workflows/ci.yml`, `.github/workflows/auto-merge.yml`, rulesets, dependency-pin changes, secrets, MY-1768 implementation paths/tests, and any additional implementation or test harness.

## Compatibility

- **User/runtime behavior**: recording, transcription, refinement, UI, persistence, privacy, telemetry, and app APIs are unchanged.
- **Release platform and lane**: macOS remains the only authorized TestFlight platform. Existing runner labels, secret names, build/upload lane, ASC counter, project marketing version, and disabled iOS lane remain compatible and unchanged.
- **Manual operation**: `workflow_dispatch`, `force`, and the marker name remain. Force can bypass relevance only, never marker equality or safety checks.
- **CI/merge contract**: `.github/workflows/ci.yml`, required check names, shared-ci pin, and repository ruleset files stay unchanged. Enforced branch-up-to-date status and PR Manager App-identity merge are external delivery prerequisites; their configuration/remediation is outside PR #101.
- **Dependencies**: no package or service is added. MY-1768 remains a hard delivery prerequisite. AppleUITesting remains pinned at `e6be2fcdf83341a9f3000a4cc489237655461a07`, and the release workflow now enforces that existing full-SHA pin and verifies checkout equality; LokiKit and shared-ci pins remain unchanged.
- **Data/config**: there is no schema, user-data migration, new workflow store, label contract, or cursor. `testflight/macos-last-released` remains the sole persistent release-state marker.
- **Rollback**: reverting these seven paths restores manual-only release and its matching tests/canonical rule. Already uploaded TestFlight builds remain external state and are not rolled back.

## Removed behavior

- **RB-001 (Owner-approved by D-001/D-012)**: the manual-only workflow/job guard and assertions forbidding non-manual triggers are replaced by exact `main`-push/`github.sha` guards.
- **RB-002 (Owner-approved by D-001 and D-008)**: `force=true` no longer permits re-upload of the SHA already stored in the marker; it bypasses only path relevance for an unreleased candidate.
- **RB-003 (Lead-approved by D-009)**: the unimplemented v3 label/API/first-parent/version-validation, Fastlane-output, rich-state, broad-documentation, CAS, and shadow-policy proposals are removed from MY-1765.
- **RB-004 (Lead-approved by D-009, reconciled by D-012/D-013)**: static tests that encode manual-only or duplicate workflow-policy logic are replaced by focused tests of the production classifier. The existing freshness and packaging contract tests are preserved and narrowly adapted to the push trigger and accepted job boundary; neither is deleted or expanded into new Fastlane behavior. Workflow lint remains the existing shared-ci check invoked by `scripts/verify --policy`; no new test path or feature-owned shadow-policy suite is added.
- **RB-005 (repository contract enforced by D-011)**: the release workflow's floating AppleUITesting checkout is replaced with the existing repository full-SHA pin plus an exact-HEAD verification. No dependency pin value or fetch script changes.

No existing secret, signing step, macOS build/upload lane, packaging test, concurrency serialization, marker, required check, or iOS guard may be removed or weakened.

## Edge cases

- A non-push/non-main automatic event or checkout mismatch stops before signing/build/upload.
- An absent marker is a bootstrap release; a present but unresolved/non-ancestor marker fails closed.
- Mixed relevant/irrelevant changes release; an exact no-match `marker..candidate` range skips unless manual force is valid.
- Marker equality skips before force. A repeated automatic evaluation of the same push SHA after a successful marker move does not upload.
- Build, upload, or pre-marker-cleanup failure leaves the marker unchanged. Marker write starts only after those steps succeed; a determinately rejected write leaves the marker unchanged, while an unconfirmed remote push reports the sole external ambiguity and stops without retry or additional state.
- Failure-capable cleanup executes with `always()` before the marker write and blocks it on failure. Marker advancement pushes the candidate directly to the remote tag ref without creating new local-tag state; any later reporting/housekeeping is warning-only/non-failing, so no later failure can produce a failed job with an advanced marker.
- MY-1768 absent, unaccepted, or not an ancestor blocks publication. Rebase conflicts or source adjustments return to the classifier/workflow tasks and invalidate earlier exact-head evidence.

## Non-goals

- Authorizing iOS TestFlight or changing product/project source.
- Editing Fastlane behavior, any test path beyond the three declared paths, CI, rulesets, required checks, dependency-pin values, secrets, MY-1768's signing/profile repair, or any `AGENTS.md` rule outside the narrow TestFlight delivery reconciliation.
- Removing or editing `.github/workflows/auto-merge.yml`, enforcing branch-up-to-date status, or changing merge identity; separate Lead/ruleset work owns those external prerequisites.
- Adding release labels, PR/label API lookup, version-transition validation, Fastlane outputs, CAS, shadow-policy suites, schedulers, release environments, rich state, attempted/skip records, cursors, retries, reconciliation, rollback, or fallback SHAs.
- Guaranteeing a transactional exactly-once operation across App Store Connect upload and Git marker update.
- Recording post-merge TestFlight success before an eligible merge actually runs.

## Measurable outcomes

- **SC-001**: For the first eligible post-merge SHA, triggering `github.sha` = checked-out SHA = uploaded source SHA = moved marker SHA, with one macOS upload reported.
- **SC-002**: All focused classifier fixtures and workflow-lint checks produce the specified release/skip/fail shape, including marker equality, bootstrap, force, and invalid ancestry.
- **SC-003**: A docs/spec/other-CI-only range executes no signing/build/upload and records the irrelevant-path skip.
- **SC-004**: Every failure before the marker attempt and every determinately rejected marker write leaves the marker unchanged and schedules no retry. Successful upload and every failure-capable cleanup step precede the sole marker move, the marker push creates no new local tag, and post-marker reporting/housekeeping cannot fail the job. An unconfirmed remote push is recorded only as the sole external ambiguity; no additional persistent state exists.
- **SC-005**: MY-1765 records the live TestFlight run URL, triggering push SHA, marketing version, and increasing build number after the first eligible merged run.
