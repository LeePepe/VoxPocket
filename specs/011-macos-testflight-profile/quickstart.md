# Quickstart: Validate portable macOS TestFlight signing

## Safety boundary

All implementation verification in this guide is credential-free. Do not run `fastlane mac beta`, create a signed archive, upload a build, install/launch a delivery build, change a keychain, or dispatch `.github/workflows/testflight.yml`. The real workflow is an Owner-controlled post-merge step.

## Prerequisites

- Work in the registered task checkout on the approved VoxPocket base.
- Use Python 3.11+ and the repository's installed Fastlane/XcodeGen environment.
- Fetch AppleUITesting only through `scripts/ci/fetch-external-deps.sh` at the repository-authorized pin.
- Record the candidate SHA/tree only after all implementation files are frozen.

## 1. Prove the regression is red first

After adding only the new freshness assertions and before production repair, run:

```sh
python3 -B scripts/tests/test_testflight_freshness.py
```

Expected: failure cites the fixed macOS profile-name/handoff or personal installer-subject contract. Record the command and concise failing assertion; do not weaken it.

## 2. Focused credential-free checks

```sh
python3 -B scripts/tests/test_testflight_freshness.py

GEM_PATH="$(brew --prefix fastlane)/libexec" \
RUBY="$(brew --prefix ruby)/bin/ruby" \
  python3 scripts/ci/run_repository_tests.py packaging-ruby

ruby -c fastlane/Fastfile
```

Expected: freshness and Ruby packaging tests pass; Fastfile reports `Syntax OK`; no credential, signing, network, upload, or keychain operation occurs.

## 3. Regenerate and check the project source of truth

From `VoxPocket/`:

```sh
xcodegen generate --spec project.yml
git diff --check
git hash-object VoxPocket.xcodeproj/project.pbxproj
xcodegen generate --spec project.yml
git hash-object VoxPocket.xcodeproj/project.pbxproj
```

Expected: the two generated-project hashes match for the same executable, and the diff contains only the planned Release signing handoff plus membership for `AppPersistenceStartup.swift`, `DefaultStageTextModelService.swift`, `MacOSAppScenes.swift`, `SettingsView.swift`, `StageModelRouting.swift`, `AppPersistenceStartupTests.swift`, and `RealtimeTranscriberConfigurationTests.swift`. Those seven files are already tracked and selected by the baseline directory-source declarations. No Swift source or generated project is hand-edited. If any additional membership or semantic build-setting drift appears, stop and return it to Team Lead.

## 4. Repository gates

From repository root:

```sh
python3 scripts/ci/run_repository_tests.py app-python
scripts/verify --policy
scripts/verify --layer VoxPocketApp
scripts/verify
scripts/verify --all
```

Expected: all commands exit 0. Local commands do not produce a signed archive or upload. The required CI App-target lane supplies unsigned macOS/iOS build evidence on the published head.

## 5. Freeze and review before publication

Record:

- base SHA;
- exact changed-path manifest;
- `git diff --check` result;
- focused and repository gate results;
- generated-project idempotency hashes;
- frozen-tree hash/manifest.

Request exact AI Reviewer content review for that frozen tree. No commit, push, or PR creation/update occurs until `PASS` and explicit publication permission. Any content change invalidates the verdict and returns to this step.

## 6. Publish the unchanged reviewed candidate

After permission only:

- commit/push the unchanged reviewed tree;
- create or update a non-Draft important PR;
- include Existing behaviour, Intent, Compatibility, Removed/weakened tests, and exact-SHA test evidence;
- require Owner approval for CODEOWNERS paths;
- prove local SHA = remote branch OID = PR `headRefOid`;
- hand the mapping to PR Manager for required checks and merge.

## 7. Owner-controlled production validation

Only after reviewed merge and explicit current Owner authorization, the authorized operator may run:

```sh
gh workflow run testflight.yml --repo LeePepe/VoxPocket --ref main -f force=true -f platform=macos
```

Record only the consent reference, run URL, exact `main` SHA, build number, terminal conclusion, and non-sensitive warnings. Do not record profile values/contents, certificate identifiers, key material, or keychain output.

Expected: macOS archive/export produces a `.pkg`, upload/processing completes, and the issue receives the run URL and build number. If it fails, preserve the exact non-sensitive error class and route current-version repair through Team Lead; do not mutate runner credentials or signing state.
