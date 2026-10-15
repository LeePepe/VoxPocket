# Verification quickstart

Run from the task-owned VoxPocket checkout. Put Python 3.11+ first on `PATH`. Do not run local archive/sign/upload/TestFlight or local `xcodebuild`.

## Feature-specific evidence

Run the focused unit tests against the production relevance classifier:

```sh
python3 scripts/tests/test_testflight_schedule.py
```

The direct input fixtures must exercise `scripts/ci/testflight_relevance.py` itself. Cover absent-marker bootstrap, marker equal to candidate, valid-ancestor and invalid/non-ancestor marker status, exact relevant/irrelevant/mixed path lists for `Packages/**`, `VoxPocket/**`, `VoxPocketWidget/**`, `fastlane/**`, `.github/workflows/testflight.yml`, and `scripts/ci/fetch-external-deps.sh`, accumulated relevance, malformed path input failing closed, and manual `force` bypassing relevance only. The suite must not parse the workflow as a shadow policy, invoke Git/GitHub, or introduce a CAS/state-machine harness.

Run the two existing focused workflow/job-boundary contract tests after adapting only their obsolete trigger/topology assumptions:

```sh
python3 scripts/tests/test_testflight_freshness.py
GEM_PATH="$(brew --prefix fastlane)/libexec" "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb
```

Freshness must assert `push: branches: [main]`, automatic candidate/checkout equality with `github.sha`, the retained manual frozen-`main` fallback, least-privilege jobs, cleanup, and terminal marker behavior. Packaging must preserve its existing no-build mocked lane coverage and the unpublished repair's `FORCE_INPUT`, dependent marker-job, `GITHUB_TOKEN`, authenticated fetch/push, and terminal marker assertions. Do not add a test path or change Fastlane behavior.

Run the repository workflow lint through its declared policy entry point:

```sh
scripts/verify --policy
```

Feature-owned verification is limited to the production-classifier tests, the two existing focused contract-test paths, and repository workflow lint. The linted workflow must show `push: branches: [main]`, exact `github.sha`, `fetch-depth: 0`, AppleUITesting checkout at and equality verification against `e6be2fcdf83341a9f3000a4cc489237655461a07`, release-job `contents: read`, dependent marker-job `contents: write`, one queued concurrency group with `cancel-in-progress: false`, unchanged existing macOS lane, upload and all failure-capable cleanup/action post-steps before marker advancement, direct authenticated candidate-to-remote-tag marker push without new local-tag state, and warning-only/non-failing post-marker reporting/housekeeping.

## Normal repository gates

The narrow feature-test shape does not waive repository delivery gates:

```sh
scripts/verify
scripts/verify --all
```

`.github/**` forces full verification; do not narrow it. Heavy app Xcode build remains CI-only.

## Exact-head PR evidence

1. Verify MY-1768 is merged and its issue records the accepted successful manual TestFlight run URL/build number.
2. Capture the exact `main` revision containing that merge; rebase MY-1765 onto it and prove the final head descends from it. Any conflict or source adjustment returns to T001–T002.
3. Confirm the candidate changes exactly `.github/workflows/testflight.yml`, `scripts/ci/testflight_relevance.py`, `scripts/tests/test_testflight_schedule.py`, `scripts/tests/test_testflight_freshness.py`, `scripts/tests/test_testflight_packaging.rb`, `docs/testflight-release.md`, and `Last-Reviewed` plus the narrow TestFlight delivery-rule wording in `AGENTS.md`; no other test path or `AGENTS.md` rule may change.
4. Rerun classifier tests, both focused contract tests, workflow lint, and every normal repository verification command after the rebase, then capture local `git rev-parse HEAD`.
5. Verify the local SHA equals the pushed branch SHA and PR `headRefOid` byte-for-byte.
6. Fill Existing behaviour, Intent, Compatibility, Removed or weakened tests or policy, and Test evidence. Declare RB-001–RB-005, superseded T003/T004 and US3/AC2–AC3/FR-007 behavior, the MY-1768 dependency revision/evidence, and no test-file deletion.
7. Confirm `docs/testflight-release.md`, the workflow, the focused contract tests, and the canonical TestFlight rule in `AGENTS.md` agree; add `owner-review`; obtain independent prepublication approval, Owner CODEOWNER approval, and all repository-required checks on that SHA. Before merge, confirm external branch-up-to-date enforcement and PR Manager App-identity merge readiness; do not change the ruleset or `auto-merge.yml` in PR #101.
8. A rebase or new push invalidates all earlier local/review/check evidence.

## Post-merge outcome evidence

For the next eligible merge after its automatic release run finishes, record on MY-1765:

- merged/released SHA;
- triggering `main` push SHA and automatic TestFlight run URL;
- uploaded outcome;
- effective marketing version and build number;
- `testflight/macos-last-released` resolving to the same SHA and confirmation that it is the sole persistent workflow release-state marker;
- confirmation that only one upload ran for that SHA.

A skipped ineligible merge, fixture, local test, or pre-merge PR run does not satisfy US4/AC4. Required PR CI/up-to-date/App-identity evidence is an external prerequisite, not the release trigger. Capture the outcome through the separate T006 Outcome Check/condition wakeup; an implementation run must not wait in the background or retry a failed/ambiguous upload automatically.
