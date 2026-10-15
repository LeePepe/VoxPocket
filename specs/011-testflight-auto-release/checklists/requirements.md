# Specification quality checklist: Automatic TestFlight release

**Purpose**: validate specification completeness before independent review
**Created**: 2026-10-15
**Spec**: [`../spec.md`](../spec.md)

## Content quality

- [x] Actors, observable outcome, constraints, non-goals, and authority are explicit.
- [x] Stable acceptance IDs are append-only and independently testable: all 18 ACs and all 12 FRs remain traceable.
- [x] Existing behavior, compatibility, and removed behavior are separate and complete.
- [x] RB-001–RB-005 identify obsolete or superseded tests/proposals and the floating dependency checkout replacement; no undeclared behavior removal exists.
- [x] D-009 remains active except for trigger/permission/test-surface details explicitly superseded or reconciled by D-012/D-013; earlier conflicting text remains visible as history.
- [x] No unresolved clarification placeholder remains.

## Minimal-shape requirement completeness

- [x] Automatic entry is `push: branches: [main]`, using exactly `github.sha` and full Git history; manual frozen-`main` fallback remains.
- [x] App relevance is exactly `testflight/macos-last-released..candidate` over `Packages/**`, `VoxPocket/**`, `VoxPocketWidget/**`, `fastlane/**`, `.github/workflows/testflight.yml`, and `scripts/ci/fetch-external-deps.sh`; bootstrap, equal-marker, ancestor, non-ancestor, relevant, irrelevant, mixed, failure, and manual-force behavior are deterministic.
- [x] The existing macOS build/upload lane, App Store Connect latest+1 counter, runner labels, step-scoped secrets, AppleUITesting pin, and disabled iOS boundary are preserved without Fastlane/project changes; D-009 adds and orders the baseline-missing cleanup, and the release checkout sets and verifies the existing AppleUITesting full SHA.
- [x] The sole marker advances only after successful upload and all failure-capable cleanup. Skips, pre-marker failures, and determinately rejected marker writes leave it unchanged; an unconfirmed remote push is the sole reported external ambiguity. No per-SHA attempted/skip state, cursor, alternate SHA, reconciliation, CAS boundary, rollback, or automatic retry exists.
- [x] Release-job permission is `contents: read` and only the dependent marker job has `contents: write`; one concurrency group queues runs with `cancel-in-progress: false`; failure-capable temporary keychain/local-tag cleanup and action post-steps finish before the marker job, marker push creates no new local tag, and post-marker reporting/housekeeping is warning-only/non-failing.
- [x] Feature-specific verification is limited to production-classifier unit tests, the two existing focused workflow/packaging contract tests, and repository workflow lint; obsolete assertions are replaced without a new path or parallel policy implementation.
- [x] The seven implementation paths are exhaustive: workflow, production classifier, classifier tests, existing freshness test, existing packaging test, direct release guide, and `Last-Reviewed` plus narrow canonical TestFlight delivery-rule wording in `AGENTS.md`.
- [x] All other test paths and `AGENTS.md` rules, broad docs, Fastlane behavior, product/project files, CI/`auto-merge.yml`/rulesets, dependency-pin changes, secrets, iOS authorization, and MY-1768 code are explicitly excluded.

## Task and delivery completeness

- [x] Active execution is T001 → T002 → T005 → T006; T003/T004 remain visible as superseded/non-executable identifiers.
- [x] Every stable AC and FR maps either to an executable task or to explicit D-009 supersession; every executable task has owner, paths/evidence surface, exclusions, dependencies, and verification.
- [x] Exact-head delivery and the no-code post-merge Outcome Check are separate tasks.
- [x] Merged+accepted MY-1768 is a hard T005 prerequisite; post-dependency rebase, ancestry proof, evidence invalidation, and conflict/source-change loopback to T001–T002 are specified without absorbing its signing repair.
- [x] Branch-up-to-date enforcement and PR Manager App-identity merge are external T005 prerequisites; separate Lead-owned `auto-merge.yml` removal is not part of PR #101.

## Repository contract

- [x] Baseline/origin/shared-ci pin, constitution, layer map, effective CODEOWNERS, required checks, and live/tracked main protection were verified.
- [x] Implementation is one protected `_root support` goal; the canonical delivery rule is reconciled with D-001/D-010/D-012, and no product layer or dependency-direction change is proposed.
- [x] Local verification excludes heavy Xcode/delivery actions and retains normal repository gates in addition to the narrow feature-specific tests.
- [x] Plan review uses exact blob/revision evidence; implementation still requires fresh AI Reviewer approval, the MY-1768 gate, and Owner execution/CODEOWNER approval.

**Result**: READY for a fresh independent AI Reviewer Spec/Standards gate. Implementation remains blocked until that exact revision passes and the T005 MY-1768 prerequisite is satisfied.
