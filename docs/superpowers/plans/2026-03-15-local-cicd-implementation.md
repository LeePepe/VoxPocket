# Local CI/CD Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-only CI/CD workflow that auto-releases on `dev -> main` merges, updates Xcode versions, generates changelogs, builds artifacts, and stores release outputs under `releases/`.

**Architecture:** Keep the release system as repository-owned shell scripts plus a versioned `.githooks/post-merge` entry point. Split responsibilities into small scripts for trigger detection, version math, changelog generation, build/export, and final release orchestration so the behavior can be tested without requiring a full app build for every script test.

**Tech Stack:** `zsh`, `git`, `xcodebuild`, `swift test`, `PlistBuddy`, Xcode project build settings, repository-local hook configuration

---

## Chunk 1: Script Skeleton And Test Harness

### Task 1: Create script directories and a shell test harness

**Files:**
- Create: `scripts/ci/common.sh`
- Create: `scripts/ci/tests/test_runner.sh`
- Create: `scripts/ci/tests/version_tests.sh`
- Create: `scripts/ci/tests/changelog_tests.sh`
- Create: `scripts/ci/tests/trigger_tests.sh`
- Create: `scripts/ci/tests/helpers.sh`

- [ ] **Step 1: Write the failing test harness**

```zsh
#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=$(cd -- "${0:A:h}" && pwd)

"$SCRIPT_DIR/version_tests.sh"
"$SCRIPT_DIR/changelog_tests.sh"
"$SCRIPT_DIR/trigger_tests.sh"
```

- [ ] **Step 2: Run test harness to verify it fails**

Run: `zsh scripts/ci/tests/test_runner.sh`
Expected: FAIL because the referenced test files or helper functions do not exist yet

- [ ] **Step 3: Write the minimal test harness support**

```zsh
#!/bin/zsh
set -euo pipefail

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$expected" == "$actual" ]] || fail "$message (expected=$expected actual=$actual)"
}
```

- [ ] **Step 4: Re-run the harness**

Run: `zsh scripts/ci/tests/test_runner.sh`
Expected: FAIL in the first real test file, proving the harness is now executing tests

- [ ] **Step 5: Commit**

```bash
git add scripts/ci/tests
git commit -m "test: add local CI shell test harness"
```

## Chunk 2: Version Calculation And Xcode Version Updates

### Task 2: Add version parsing and bump tests first

**Files:**
- Create: `scripts/ci/version.sh`
- Modify: `scripts/ci/tests/version_tests.sh`
- Modify: `scripts/ci/tests/helpers.sh`
- Test: `scripts/ci/tests/version_tests.sh`

- [ ] **Step 1: Write failing version tests**

```zsh
assert_eq "1.4.0" "$(next_marketing_version 1.3.2 minor)" "minor releases should reset patch"
assert_eq "1.4.1" "$(next_marketing_version 1.4.0 patch)" "patch releases should increment patch"
assert_eq "2.0.0" "$(next_marketing_version 1.4.3 major)" "major releases should reset minor and patch"
assert_eq "42" "$(next_build_number 41)" "build number should increment"
```

- [ ] **Step 2: Run only the version tests to verify they fail**

Run: `zsh scripts/ci/tests/version_tests.sh`
Expected: FAIL because `next_marketing_version` and `next_build_number` are undefined

- [ ] **Step 3: Implement minimal version math**

```zsh
next_marketing_version() {
  local current="$1"
  local bump="$2"
  local major minor patch
  IFS=. read -r major minor patch <<<"$current"
  case "$bump" in
    major) print -- "$((major + 1)).0.0" ;;
    minor) print -- "$major.$((minor + 1)).0" ;;
    patch) print -- "$major.$minor.$((patch + 1))" ;;
    *) return 1 ;;
  esac
}

next_build_number() {
  print -- "$(($1 + 1))"
}
```

- [ ] **Step 4: Re-run version tests to verify they pass**

Run: `zsh scripts/ci/tests/version_tests.sh`
Expected: PASS

- [ ] **Step 5: Add failing tests for reading and writing Xcode project versions**

```zsh
assert_eq "1.0" "$(project_marketing_version "$fixture_project")" "should read marketing version"
assert_eq "1" "$(project_build_number "$fixture_project")" "should read build number"
```

- [ ] **Step 6: Run version tests and verify the new cases fail**

Run: `zsh scripts/ci/tests/version_tests.sh`
Expected: FAIL because project read/write helpers are missing

- [ ] **Step 7: Implement Xcode project read/write helpers**

Use `sed`/`perl`-safe file replacement around:

```zsh
project_marketing_version() { ... }
project_build_number() { ... }
set_project_versions() { ... }
```

- [ ] **Step 8: Re-run version tests**

Run: `zsh scripts/ci/tests/version_tests.sh`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add scripts/ci/version.sh scripts/ci/tests/version_tests.sh scripts/ci/tests/helpers.sh
git commit -m "feat: add local release version management"
```

## Chunk 3: Trigger Detection For `post-merge`

### Task 3: Drive branch and merge-source detection with tests

**Files:**
- Create: `scripts/ci/trigger.sh`
- Modify: `scripts/ci/tests/trigger_tests.sh`
- Test: `scripts/ci/tests/trigger_tests.sh`

- [ ] **Step 1: Write failing trigger tests**

```zsh
assert_eq "yes" "$(should_run_release main dev clean merge)" "main receiving dev merge should trigger"
assert_eq "no" "$(should_run_release dev feature/foo clean merge)" "dev branch should not trigger"
assert_eq "no" "$(should_run_release main dev dirty merge)" "dirty worktree should not trigger"
assert_eq "yes" "$(release_bump_kind main hotfix/audio)" "hotfix merges should map to patch"
```

- [ ] **Step 2: Run trigger tests to verify they fail**

Run: `zsh scripts/ci/tests/trigger_tests.sh`
Expected: FAIL because trigger helpers do not exist

- [ ] **Step 3: Implement minimal trigger helpers**

```zsh
should_run_release() {
  local branch="$1"
  local source="$2"
  local worktree_state="$3"
  local event_kind="$4"
  ...
}
```

- [ ] **Step 4: Re-run trigger tests**

Run: `zsh scripts/ci/tests/trigger_tests.sh`
Expected: PASS

- [ ] **Step 5: Add failing tests for merge-commit parsing**

```zsh
assert_eq "dev" "$(merge_source_from_subject "Merge branch 'dev'")" "should detect dev source"
assert_eq "hotfix/audio" "$(merge_source_from_subject "Merge branch 'hotfix/audio'")" "should detect hotfix source"
```

- [ ] **Step 6: Re-run trigger tests to verify they fail**

Run: `zsh scripts/ci/tests/trigger_tests.sh`
Expected: FAIL because merge subject parsing is missing

- [ ] **Step 7: Implement merge subject parsing**

Use a small parser that handles local merge subjects of the form:

```text
Merge branch 'dev'
Merge branch 'hotfix/audio'
```

- [ ] **Step 8: Re-run trigger tests**

Run: `zsh scripts/ci/tests/trigger_tests.sh`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add scripts/ci/trigger.sh scripts/ci/tests/trigger_tests.sh
git commit -m "feat: add local release trigger detection"
```

## Chunk 4: Changelog Generation

### Task 4: Add changelog generation with tag-range tests

**Files:**
- Create: `scripts/ci/changelog.sh`
- Modify: `scripts/ci/tests/changelog_tests.sh`
- Test: `scripts/ci/tests/changelog_tests.sh`

- [ ] **Step 1: Write failing changelog tests**

```zsh
assert_contains "## Features" "$(render_changelog "$commits_fixture")" "should create a features section"
assert_contains "- add local release version management" "$(render_changelog "$commits_fixture")" "feat commits should be included"
assert_contains "## Fixes" "$(render_changelog "$commits_fixture")" "fix commits should be grouped"
```

- [ ] **Step 2: Run changelog tests to verify they fail**

Run: `zsh scripts/ci/tests/changelog_tests.sh`
Expected: FAIL because `render_changelog` is undefined

- [ ] **Step 3: Implement minimal changelog rendering**

Support:
- `feat: ...` => `## Features`
- `fix: ...` => `## Fixes`
- everything else => `## Maintenance`

- [ ] **Step 4: Re-run changelog tests**

Run: `zsh scripts/ci/tests/changelog_tests.sh`
Expected: PASS

- [ ] **Step 5: Add failing tests for git-log based changelog extraction**

```zsh
assert_contains "feat: sample feature" "$(changelog_from_git_range "$repo_fixture" "v1.0.0" "HEAD")" "should read commits from git"
```

- [ ] **Step 6: Re-run changelog tests to verify they fail**

Run: `zsh scripts/ci/tests/changelog_tests.sh`
Expected: FAIL because git range extraction is missing

- [ ] **Step 7: Implement git-range changelog extraction**

Expose:

```zsh
latest_release_tag() { ... }
changelog_from_git_range() { ... }
write_changelog_file() { ... }
```

- [ ] **Step 8: Re-run changelog tests**

Run: `zsh scripts/ci/tests/changelog_tests.sh`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add scripts/ci/changelog.sh scripts/ci/tests/changelog_tests.sh
git commit -m "feat: add local release changelog generation"
```

## Chunk 5: Release Directory Metadata And Build Export

### Task 5: Add release output structure and metadata tests first

**Files:**
- Create: `scripts/ci/build.sh`
- Create: `scripts/ci/release_metadata.sh`
- Create: `scripts/ci/tests/release_output_tests.sh`
- Modify: `scripts/ci/tests/test_runner.sh`
- Test: `scripts/ci/tests/release_output_tests.sh`

- [ ] **Step 1: Write failing release output tests**

```zsh
assert_file_exists "$tmpdir/releases/v1.4.0/CHANGELOG.md"
assert_file_exists "$tmpdir/releases/v1.4.0/release.json"
assert_file_exists "$tmpdir/releases/v1.4.0/artifacts/VoxPocket.app"
```

- [ ] **Step 2: Run release output tests to verify they fail**

Run: `zsh scripts/ci/tests/release_output_tests.sh`
Expected: FAIL because the release output writers do not exist

- [ ] **Step 3: Implement release output writers**

Add helpers to:
- create a staging release directory
- copy artifacts into `artifacts/`
- write `release.json`
- finalize the staged directory atomically

- [ ] **Step 4: Re-run release output tests**

Run: `zsh scripts/ci/tests/release_output_tests.sh`
Expected: PASS

- [ ] **Step 5: Add failing build command composition tests**

```zsh
assert_contains "-project VoxPocket/VoxPocket.xcodeproj" "$(build_command "$repo_root" "$derived_data")" "should target the app project"
assert_contains "-scheme VoxPocket" "$(build_command "$repo_root" "$derived_data")" "should use VoxPocket scheme"
```

- [ ] **Step 6: Re-run release output tests to verify they fail**

Run: `zsh scripts/ci/tests/release_output_tests.sh`
Expected: FAIL because build command generation is missing

- [ ] **Step 7: Implement build command generation and artifact export**

Provide:

```zsh
build_command() { ... }
run_build() { ... }
collect_app_artifact() { ... }
```

- [ ] **Step 8: Re-run release output tests**

Run: `zsh scripts/ci/tests/release_output_tests.sh`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add scripts/ci/build.sh scripts/ci/release_metadata.sh scripts/ci/tests/release_output_tests.sh scripts/ci/tests/test_runner.sh
git commit -m "feat: add local release output packaging"
```

## Chunk 6: Release Orchestration

### Task 6: Add orchestration tests before wiring the full release script

**Files:**
- Create: `scripts/ci/release.sh`
- Modify: `scripts/ci/tests/helpers.sh`
- Create: `scripts/ci/tests/release_tests.sh`
- Modify: `scripts/ci/tests/test_runner.sh`
- Test: `scripts/ci/tests/release_tests.sh`

- [ ] **Step 1: Write failing orchestration tests**

```zsh
assert_contains "minor" "$(default_bump_for_source dev)" "dev merges should default to minor"
assert_contains "patch" "$(default_bump_for_source hotfix/audio)" "hotfix merges should default to patch"
assert_contains "v1.4.0" "$(release_tag_for 1.4.0)" "tag generation should prepend v"
```

- [ ] **Step 2: Run release orchestration tests to verify they fail**

Run: `zsh scripts/ci/tests/release_tests.sh`
Expected: FAIL because the release orchestration helpers do not exist

- [ ] **Step 3: Implement minimal orchestration helpers**

Expose:

```zsh
default_bump_for_source() { ... }
release_tag_for() { ... }
release_pipeline() { ... }
```

- [ ] **Step 4: Re-run release tests**

Run: `zsh scripts/ci/tests/release_tests.sh`
Expected: PASS

- [ ] **Step 5: Add failing integration-style tests with stubbed build/changelog writers**

Create a temp fixture repo and assert that `release_pipeline`:
- updates versions
- writes release directory
- creates a release commit
- creates a tag

- [ ] **Step 6: Run release orchestration tests to verify they fail**

Run: `zsh scripts/ci/tests/release_tests.sh`
Expected: FAIL because the orchestration is not yet complete

- [ ] **Step 7: Implement full release orchestration**

Behavior:
- validate branch/source/worktree
- read current versions
- compute next versions
- update project file
- generate changelog
- build/export artifact
- write metadata
- commit release changes
- tag release

- [ ] **Step 8: Re-run release tests**

Run: `zsh scripts/ci/tests/release_tests.sh`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add scripts/ci/release.sh scripts/ci/tests/release_tests.sh scripts/ci/tests/helpers.sh scripts/ci/tests/test_runner.sh
git commit -m "feat: add local release orchestration"
```

## Chunk 7: Hook Integration And Enablement

### Task 7: Add hook tests and install flow

**Files:**
- Create: `.githooks/post-merge`
- Create: `scripts/ci/install-hooks.sh`
- Create: `scripts/ci/tests/hook_tests.sh`
- Modify: `scripts/ci/tests/test_runner.sh`
- Test: `scripts/ci/tests/hook_tests.sh`

- [ ] **Step 1: Write failing hook tests**

```zsh
assert_contains "scripts/ci/release.sh" "$(cat .githooks/post-merge)" "hook should invoke release entrypoint"
assert_contains "core.hooksPath" "$(zsh scripts/ci/install-hooks.sh --print-command)" "installer should configure repo hooks"
```

- [ ] **Step 2: Run hook tests to verify they fail**

Run: `zsh scripts/ci/tests/hook_tests.sh`
Expected: FAIL because the hook and installer do not exist

- [ ] **Step 3: Implement minimal hook and install script**

Hook behavior:
- exit early unless on `main`
- inspect `HEAD` merge subject
- call `scripts/ci/release.sh --auto`

Installer behavior:
- run `git config core.hooksPath .githooks`
- support a `--print-command` mode for testability

- [ ] **Step 4: Re-run hook tests**

Run: `zsh scripts/ci/tests/hook_tests.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add .githooks/post-merge scripts/ci/install-hooks.sh scripts/ci/tests/hook_tests.sh scripts/ci/tests/test_runner.sh
git commit -m "feat: add local release hook integration"
```

## Chunk 8: Documentation And Final Verification

### Task 8: Document usage and run end-to-end verification

**Files:**
- Create: `docs/local-cicd.md`
- Modify: `AGENTS.md`
- Test: `scripts/ci/tests/test_runner.sh`
- Test: `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build`

- [ ] **Step 1: Write documentation updates**

Document:
- branch model (`feature/* -> dev -> main`)
- version rules (`major.minor.patch` + build)
- how to install hooks
- how release auto-trigger works
- where outputs appear under `releases/`
- how to run local script tests manually

- [ ] **Step 2: Run shell test suite**

Run: `zsh scripts/ci/tests/test_runner.sh`
Expected: PASS

- [ ] **Step 3: Run project build verification**

Run: `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Inspect git diff and ensure only intended files changed**

Run: `git status --short`
Expected: only local CI/CD files and docs are modified

- [ ] **Step 5: Commit**

```bash
git add docs/local-cicd.md AGENTS.md scripts/ci .githooks
git commit -m "docs: document local CI workflow"
```

- [ ] **Step 6: Final verification**

Run:

```bash
zsh scripts/ci/tests/test_runner.sh
xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build
```

Expected: all shell tests pass and app build succeeds
