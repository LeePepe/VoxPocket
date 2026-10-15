# Research: Automatic macOS TestFlight CD on merge to main

**Baseline**: `ef1420234d2b56fddcf2a388eaabf97ec54126d4`
**Date**: 2026-10-15
**Active authority**: MY-1777 minimal-shape decision `01a13cc2-c043-7989-b6ae-da334ba1d333`, adopted for MY-1765 by `01a13cc2-e49a-7db2-9792-630c36ea6206`, with the trigger mechanically superseded by Owner CD-on-merge decision `01a13ee3-fce1-7432-9144-64cd9077e5a3` and Team Lead reconciliation `01a13ee7-76ad-71ad-a669-1bb2985ed17c`

## R-001 — Repository, layer, and protected-workflow authority

**Evidence**: origin is `LeePepe/VoxPocket`; planning baseline `HEAD == ef1420234d2b56fddcf2a388eaabf97ec54126d4`. `AGENTS.md` pins shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c` and is the canonical repository-rule source via `CLAUDE.md`. Its baseline TestFlight rule still requires manual dispatch after an explicit Owner request, while D-001/D-012 authorize automatic exact-`main`-push release. The constitution and `docs/architecture/tech-context.md` classify `.github/**`, `scripts/**`, docs, specs, and `AGENTS.md` as `_root support`. Required PR checks, CODEOWNER review, branch-up-to-date enforcement, and PR Manager App-identity merge are delivery prerequisites; the latter two are external to PR #101.

**Decision**: deliver one protected `_root support` PR with exact-head evidence, `owner-review`, Owner approval, and normal required checks. Include only the narrow `AGENTS.md` TestFlight wording needed to reconcile the canonical rule with D-001/D-012, retaining manual fallback, protected Owner approval, and separate iOS authorization. There is no product-layer, dependency-direction, CI, ruleset, required-check, `auto-merge.yml`, or merge-identity change in PR #101.

## R-002 — Automatic trigger and immutable candidate

**Evidence**: the Owner decided that CI completes before merge and CD starts after merge. Branch-up-to-date enforcement makes PR CI test what lands, and PR Manager App-identity merge preserves push-triggered workflows. A `push` event on `main` supplies immutable `github.sha`. The baseline TestFlight workflow admits only manual events and checks out moving `main`.

**Decision**: add `push: branches: [main]`. Automatic operation selects exactly `github.sha`; checkout uses `fetch-depth: 0` and asserts checked-out `HEAD` equality. Manual dispatch resolves `main` once and freezes that SHA. Do not retain `workflow_run`, poll checks, select an alternate SHA, or re-resolve `main` after selection. Do not implement branch/ruleset or merge-identity prerequisites inside the workflow.

## R-003 — Production relevance classifier and exact range

**Evidence**: delivered-app inputs live under `Packages/**`, `VoxPocket/**`, `VoxPocketWidget/**`, `fastlane/**`, `.github/workflows/testflight.yml`, and `scripts/ci/fetch-external-deps.sh`. Documentation, specs, other workflows, and unrelated support files do not alter the app/archive. Trigger-level path filters cannot compare against the last released marker and cannot express manual force.

**Decision**: add one small production classifier at `scripts/ci/testflight_relevance.py` for that exact path set. The workflow resolves the sole marker and supplies its status; for a valid ancestor it also supplies the exact output of `git diff --name-only marker..candidate`. The classifier releases on any match, skips on no match, treats a missing marker as bootstrap, and rejects invalid/unresolved/non-ancestor status. Mixed changes release. There is no alternate diff base, symmetric diff, cursor, or duplicated shadow classifier.

## R-004 — Marker, force, ordering, and failure semantics

**Evidence**: the baseline force condition can re-upload an already marked SHA. Owner decision D-008 requires one queued concurrency group, one last-released marker, relevance over `marker..candidate`, no attempted/skip state or cursor, and fail-closed behavior without retry. MY-1777 further rejects a CAS boundary or heavier release state.

**Decision**: `testflight/macos-last-released` is the only persistent workflow state. Marker equality is a hard skip before force; manual `force` bypasses relevance only for an otherwise valid unreleased candidate. Upload and every failure-capable `always()` cleanup step complete before the remote marker is advanced; cleanup failure blocks the marker. The marker write pushes the candidate directly to the remote tag ref without creating a new local tag and is the last failure-capable state transition; any post-marker reporting/housekeeping is best-effort/non-failing with a logged warning. Every failure before that attempt, and every determinately rejected marker write, leaves the remote marker unchanged. An unconfirmed remote push is the sole external ambiguity and does not assert marker state. The run stops without automatic retry, rollback, reconciliation, fallback SHA, CAS helper, or second state mechanism; an irrelevant-path skip still records its concise reason.

## R-005 — Existing build/upload lane and counter stay unchanged

**Evidence**: `fastlane/Fastfile` already queries `latest_testflight_build_number(platform: "osx")` without a marketing-version filter, uses `latest + 1`, reads the project marketing version, builds the macOS target, and uploads to TestFlight. The existing Ruby packaging tests cover the counter, packaging, and disabled-iOS contracts.

**Decision**: invoke that lane unchanged after eligibility succeeds. Set the existing release checkout of `LeePepe/AppleUITesting` to `ref: e6be2fcdf83341a9f3000a4cc489237655461a07` and verify its checked-out `HEAD` equals that SHA before build work, matching CI's existing pin without changing it. MY-1765 does not edit Fastlane, add Fastlane outputs, change version selection, or expand the packaging tests. One non-canceling concurrency group continues to prevent overlapping counter allocation/upload. Counter or lane failure fails before marker advancement.

## R-006 — Superseded v3 version/label research

**Evidence**: v3 proposed first-parent commit enumeration, merged-PR association, `release:minor` label lookup, semantic-transition validation, `pull-requests: read`, Fastlane output changes, and label provisioning. None exists at the baseline. MY-1777 authority chooses the smaller automatic-release shape and removes this proposal from MY-1765.

**Decision**: treat v3 D-005, US3/AC2, US3/AC3, and FR-007 as superseded history only. Keep `VoxPocket/project.yml` and the lane's existing version behavior unchanged. Add no label/API lookup, PR association, version-range validation, permission for pull requests, label provisioning action, or project mutation.

## R-007 — Focused verification seam

**Evidence**: `scripts/tests/test_testflight_schedule.py` currently contains static assertions for manual-only triggering and moving-`main` checkout. Those assertions must change when automatic release is authorized. A classifier tested only through copied workflow-policy logic would create a second authority surface. The separate packaging suite already covers the unchanged lane.

**Decision**: repurpose the schedule test path into focused unit tests that import/execute the real production classifier. Preserve the already-published focused `scripts/tests/test_testflight_freshness.py` adaptation and the clean unpublished `scripts/tests/test_testflight_packaging.rb` repair, updating only their obsolete `workflow_run`/trigger assumptions and retaining their force/job-permission/terminal-marker coverage. Keep workflow lint at the existing shared-ci policy entry point, `scripts/verify --policy`. Replace obsolete assertions rather than deleting a test file. Do not add a shadow-policy suite, exhaustive workflow simulator, CAS harness, new packaging behavior, or another test path.

## R-008 — Runner, permission, secrets, and cleanup

**Evidence**: the baseline job uses `[self-hosted, macOS, ARM64]`, concurrency group `testflight` with `cancel-in-progress: false`, existing ASC/keychain secrets, temporary signing resources, a remote Git tag marker, and a disabled iOS lane. Marker update requires repository content write access; PR/label lookup has been removed.

**Decision**: retain one app-specific queued concurrency group and the runner labels. Keep the accepted least-privilege split: release job `permissions: contents: read`, dependent marker job `permissions: contents: write`, and no `pull-requests: read`. Expose build/signing secrets only on the steps that consume them. Preserve existing secret names and disabled iOS behavior. Run failure-capable `always()` cleanup and action post-steps before the marker job may start; failure blocks the marker. Push the candidate directly to the remote marker ref without a new local tag; any post-marker reporting/housekeeping absorbs its own failure and logs a warning. Do not log secrets or user content.

## R-009 — Exact owned surface and documentation boundary

**Evidence**: the accepted v5 plan started with five paths. PR #101 at `e2f290c7a8ba9f8535d1c2c2f86e11f6f420981d` publishes those paths plus `scripts/tests/test_testflight_freshness.py`. Preserved clean unpublished repair `8ebfc3c473bc88a86d93b5155d8b3b1fa1d5b9a1` changes only `scripts/tests/test_testflight_packaging.rb` to reconcile force and the dependent marker job. The v4 gate found that baseline `AGENTS.md` directly contradicts automatic release, so its narrow rule reconciliation remains required.

**Decision**: implementation owns exactly seven paths:

1. `.github/workflows/testflight.yml`
2. `scripts/ci/testflight_relevance.py`
3. `scripts/tests/test_testflight_schedule.py`
4. `scripts/tests/test_testflight_freshness.py`
5. `scripts/tests/test_testflight_packaging.rb`
6. `docs/testflight-release.md`
7. `AGENTS.md` (only `Last-Reviewed` plus the canonical TestFlight delivery-rule wording)

Explicitly exclude `fastlane/Fastfile`, every other test path, every other `AGENTS.md` rule, `docs/local-cicd.md`, product/project files, `.github/workflows/ci.yml`, `.github/workflows/auto-merge.yml`, rulesets, dependency-pin changes, secrets, and MY-1768 code/tests. The release guide documents the compatible existing lane, exact candidate/range, skip/failure behavior, force limit, marker ordering, and evidence required after merge. It does not introduce a rich outcome model or revive label/version policy.

## R-010 — Mandatory MY-1768 signing dependency

**Evidence**: Owner authority `01a13b42-e51d-732c-b0c6-9eeb3d2ab7ff` requires MY-1768 to land before or with MY-1765. Manual TestFlight run `38598643529` on baseline `ef14202` failed because the expected profile was unavailable. MY-1768 separately owns the in-run profile repair, regression coverage, and accepted successful manual TestFlight URL/build evidence.

**Decision**: retain the separate prerequisite. Publication cannot start until MY-1768 is merged and accepted. Rebase MY-1765 onto the exact `main` revision containing that merge, prove the final head descends from it, and regenerate all local/review/CI exact-head evidence. A conflict or source adjustment returns to the classifier/workflow tasks. Do not copy MY-1768 implementation/tests into MY-1765 or weaken the dependency.

## R-011 — Existing, compatible, and removed behavior synthesis

**Existing**: manual-only triggering, moving-`main` checkout, marker comparison with overbroad force, the self-hosted macOS lane/counter, the sole marker, disabled iOS, and static manual-only schedule assertions are present at baseline. Explicit temporary keychain/local-tag cleanup is absent at the declared base and is added and ordered by D-009. Published PR #101 and its preserved repair establish the seven-path implementation/test reality and least-privilege two-job marker topology that this revision carries forward.

**Compatible**: runner labels, one non-canceling concurrency group, existing secret names, the MY-1768-repaired signing contract, unchanged Fastlane lane/counter/version source, macOS-only boundary, marker name, packaging behavior, CI/checks, repository ruleset files, and dependency pin values remain in force. The release workflow newly enforces the already-authoritative AppleUITesting full SHA. Branch-up-to-date enforcement, PR Manager App-identity merge, and separate `auto-merge.yml` removal are external prerequisites, not PR #101 changes.

**Removed or replaced**: manual-only admission, the matching manual-per-upload canonical delivery wording, moving candidate selection, force-based same-SHA re-upload, obsolete static scheduling assertions, and v5 `workflow_run` assumptions are replaced. Unimplemented v3 label/API/version-range, Fastlane-output, broad-doc, rich-state, CAS, and shadow-policy proposals remain explicitly removed from the plan. No other baseline behavior is removed.
