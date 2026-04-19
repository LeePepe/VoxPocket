# Implementation Plan: VoxPocket CI/CD Release Pipeline (Personal Use)

## Status: APPROVED (v5)

## Scope Constraint
**Personal use only** — no Developer ID certificate, no App Store Connect API Key.
DMG is installable on developer's own machine only (Gatekeeper will block others).
GitHub Releases serves as version archive, not public distribution.
User merges via **GitHub PR merge button**.

## Architecture

```
merge dev → main (GitHub PR merge button)
      ↓
GitHub Actions (self-hosted macOS ARM64 — developer's own machine)
      ↓
release.sh --auto
  ├── trigger.sh: detect merge source (dev → minor, hotfix/* → patch)
  ├── version.sh: bump MARKETING_VERSION + CURRENT_PROJECT_VERSION
  ├── changelog.sh: generate from git commits
  ├── build.sh: xcodebuild archive + exportArchive (Release, development signing)
  ├── package_dmg.sh: hdiutil → .dmg
  ├── release_metadata.sh: write release.json
  ├── git commit "chore: release vX.Y.Z" + tag
  ├── git push origin main --follow-tags
  └── github_release.sh: gh release create + upload DMG
```

## Files to Change

| File | Operation | Notes |
|------|-----------|-------|
| `scripts/ci/trigger.sh` | Modify | Add GitHub PR merge format; fix zsh pattern vars |
| `scripts/ci/tests/trigger_tests.sh` | Modify | Add GitHub PR merge test cases + negative cases |
| `scripts/ci/build.sh` | Modify | Add archive/export functions; keep existing for tests |
| `scripts/ci/ExportOptions.plist` | Create | method=development, automatic signing |
| `scripts/ci/package_dmg.sh` | Create | hdiutil DMG packaging |
| `scripts/ci/github_release.sh` | Create | gh release create wrapper |
| `scripts/ci/release.sh` | Modify | Wire archive/export/DMG/GitHub Release into pipeline |
| `scripts/ci/tests/release_tests.sh` | Modify | Add mocks for run_archive, run_export_archive, package_dmg, github_release |
| `.github/workflows/release.yml` | Create | Push to main → run release pipeline |

---

## Step 0: `scripts/ci/trigger.sh` — Add GitHub PR merge format + fix zsh pattern

**Problem 1**: Only matches `Merge branch 'dev'`, not GitHub PR merge format.
**Problem 2 (CRITICAL)**: zsh `=~` with **quoted** string pattern does NOT populate `$match`.
Pattern must be assigned to a variable first, then referenced **unquoted**.

**Full rewrite of `merge_source_from_subject`**:

```zsh
merge_source_from_subject() {
  local subject="$1"
  # Use variables (not quoted literals) so zsh =~ populates $match
  local pattern_local="Merge branch '([^']+)'"
  local pattern_github='Merge pull request #[0-9]+ from [^/]+/(.+)'

  # Local merge: "Merge branch 'dev'"
  if [[ "$subject" =~ $pattern_local ]]; then
    print -- "${match[1]}"
    return 0
  fi
  # GitHub PR merge: "Merge pull request #N from owner/branch-name"
  # [^/]+ matches owner, (.+) captures full branch (including slashes e.g. hotfix/audio)
  if [[ "$subject" =~ $pattern_github ]]; then
    print -- "${match[1]}"
    return 0
  fi
  return 1
}
```

**Update `scripts/ci/tests/trigger_tests.sh`** — add after existing assertions:

```zsh
# GitHub PR merge format
assert_eq "dev" "$(merge_source_from_subject "Merge pull request #5 from LeePepe/dev")" \
  "should detect dev from GitHub PR merge"
assert_eq "hotfix/audio" "$(merge_source_from_subject "Merge pull request #6 from LeePepe/hotfix/audio")" \
  "should detect hotfix/audio from GitHub PR merge"
assert_eq "dev" "$(merge_source_from_subject "Merge pull request #1 from my-org/dev")" \
  "should handle hyphenated owner name"

# Negative cases — must NOT match
assert_eq "" "$(merge_source_from_subject "feat: add something" || true)" \
  "non-merge commit should return empty"
assert_eq "" "$(merge_source_from_subject "chore: release v1.2.0" || true)" \
  "release commit should return empty"
```

---

## Step 1: `scripts/ci/build.sh` — Add archive/export functions

Keep ALL existing functions (`build_command`, `run_build`, `collect_app_artifact`) unchanged — tests depend on them.
Add new functions alongside. **Quote all path arguments** to handle spaces.

```zsh
# --- Archive + Export (Release distribution) ---

ARCHIVE_SCHEME="VoxPocket"
ARCHIVE_CONFIGURATION="Release"

archive_command() {
  local repo_root="$1"
  local archive_path="$2"
  local derived_data="$3"
  print -- "xcodebuild \
    -project '$repo_root/VoxPocket/VoxPocket.xcodeproj' \
    -scheme $ARCHIVE_SCHEME \
    -configuration $ARCHIVE_CONFIGURATION \
    -destination 'generic/platform=macOS' \
    -archivePath '$archive_path' \
    -derivedDataPath '$derived_data' \
    CODE_SIGN_STYLE=Automatic \
    archive"
}

run_archive() {
  local repo_root="$1"
  local archive_path="$2"
  local derived_data="$3"
  local log_file="$4"
  eval "$(archive_command "$repo_root" "$archive_path" "$derived_data")" >"$log_file" 2>&1
}

export_command() {
  local archive_path="$1"
  local export_dir="$2"
  local export_options_plist="$3"
  print -- "xcodebuild \
    -exportArchive \
    -archivePath '$archive_path' \
    -exportPath '$export_dir' \
    -exportOptionsPlist '$export_options_plist'"
}

run_export_archive() {
  local archive_path="$1"
  local export_dir="$2"
  local export_options_plist="$3"
  local log_file="$4"
  eval "$(export_command "$archive_path" "$export_dir" "$export_options_plist")" >"$log_file" 2>&1
}
```

---

## Step 2: `scripts/ci/ExportOptions.plist` — Create

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
```

Compatible with Hardened Runtime + App Sandbox on developer's own machine.

---

## Step 3: `scripts/ci/package_dmg.sh` — Create

```zsh
#!/bin/zsh
set -euo pipefail

# package_dmg <app_path> <output_dir> <volume_name> <dmg_name>
# Prints the full path to the created DMG on stdout
package_dmg() {
  local app_path="$1"
  local output_dir="$2"
  local volume_name="$3"
  local dmg_name="$4"
  local tmp_base="$output_dir/.tmp-${dmg_name%.dmg}"
  local final_dmg="$output_dir/$dmg_name"
  local staging
  staging="$(mktemp -d)"
  trap 'rm -rf "$staging"' RETURN

  cp -R "$app_path" "$staging/"
  ln -s /Applications "$staging/Applications"

  hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging" \
    -ov \
    -format UDZO \
    -o "$tmp_base"

  mv "${tmp_base}.dmg" "$final_dmg"
  print -- "$final_dmg"
}
```

---

## Step 4: `scripts/ci/github_release.sh` — Create

```zsh
#!/bin/zsh
set -euo pipefail

# github_release <tag> <changelog_file> <dmg_path>
# Requires GH_TOKEN in environment (set by GitHub Actions or gh auth login)
github_release() {
  local tag="$1"
  local changelog_file="$2"
  local dmg_path="$3"

  gh release create "$tag" \
    --title "$tag" \
    --notes-file "$changelog_file" \
    "$dmg_path"
}
```

---

## Step 5: `scripts/ci/release.sh` — Modify

**Add to source block at top:**
```zsh
source "$SCRIPT_DIR/package_dmg.sh"
source "$SCRIPT_DIR/github_release.sh"
```

**Replace lines 97-98 (run_build + install_release_artifact):**

Old:
```zsh
run_build "$repo_root" "$derived_data" "$build_log"
install_release_artifact "$derived_data/Build/Products/Debug/VoxPocket.app" "$staging_dir"
```

New:
```zsh
local archive_path export_dir export_log export_options
archive_path="$derived_data/VoxPocket.xcarchive"
export_dir="$staging_dir/export"
export_log="$staging_dir/export.log"
export_options="$SCRIPT_DIR/ExportOptions.plist"

run_archive "$repo_root" "$archive_path" "$derived_data" "$build_log"
run_export_archive "$archive_path" "$export_dir" "$export_options" "$export_log"
install_release_artifact "$export_dir/VoxPocket.app" "$staging_dir"
```

**Replace `cleanup_release_failure` inner function** to also roll back local git commit and tag on failure:

Old:
```zsh
cleanup_release_failure() {
  local exit_code="$?"
  if [[ "$exit_code" -ne 0 ]]; then
    [[ -f "$backup_file" ]] && mv "$backup_file" "$project_file"
    [[ -n "$staging_dir" ]] && rm -rf "$staging_dir"
    [[ -n "$final_dir" ]] && rm -rf "$final_dir"
  else
    rm -f "$backup_file"
  fi
  return "$exit_code"
}
```

New (CRITICAL fix: roll back git commit and tag if they exist):
```zsh
cleanup_release_failure() {
  local exit_code="$?"
  if [[ "$exit_code" -ne 0 ]]; then
    [[ -f "$backup_file" ]] && mv "$backup_file" "$project_file"
    [[ -n "$staging_dir" ]] && rm -rf "$staging_dir"
    [[ -n "$final_dir" ]] && rm -rf "$final_dir"
    # Roll back release commit and tag if they were created before failure
    if [[ -n "$tag" ]] && git -C "$repo_root" tag | grep -qx "$tag" 2>/dev/null; then
      git -C "$repo_root" tag -d "$tag" >/dev/null 2>&1 || true
    fi
    # Match exact version to avoid accidentally resetting an unrelated release commit
    if git -C "$repo_root" log -1 --pretty=%s 2>/dev/null | grep -qE "^chore: release v${next_marketing}$"; then
      git -C "$repo_root" reset --hard HEAD~1 >/dev/null 2>&1 || true
    fi
  else
    rm -f "$backup_file"
  fi
  return "$exit_code"
}
```

**Replace end of `release_pipeline` (from `finalize_release_dir` to end of function):**

Old:
```zsh
finalize_release_dir "$staging_dir" "$final_dir"

git -C "$repo_root" add "$project_file"
git -C "$repo_root" commit -m "chore: release $tag" >/dev/null
git -C "$repo_root" tag "$tag"
trap - EXIT
rm -f "$backup_file"
```

New (`trap - EXIT` and `rm -f` after all network ops succeed):
```zsh
finalize_release_dir "$staging_dir" "$final_dir"

# Package DMG
local dmg_name dmg_path
dmg_name="VoxPocket-${next_marketing}.dmg"
dmg_path="$(package_dmg \
  "$final_dir/artifacts/VoxPocket.app" \
  "$final_dir/artifacts" \
  "VoxPocket $next_marketing" \
  "$dmg_name")"

# Write release metadata with DMG artifact path (releases/ is in .gitignore, not committed)
write_release_metadata "$final_dir" "$next_marketing" "$tag" \
  "$(git -C "$repo_root" rev-parse HEAD)" "$next_build" \
  "artifacts/$dmg_name"

git -C "$repo_root" add "$project_file"
git -C "$repo_root" commit -m "chore: release $tag" >/dev/null
git -C "$repo_root" tag "$tag"

# Push + GitHub Release — cleanup trap stays active until all network ops succeed
# Set VOX_CI_SKIP_GITHUB_RELEASE=1 for local runs without GH_TOKEN
if [[ "${VOX_CI_SKIP_GITHUB_RELEASE:-0}" != "1" ]]; then
  git -C "$repo_root" push origin main --follow-tags
  github_release "$tag" "$final_dir/CHANGELOG.md" "$dmg_path"
fi

# Disarm cleanup trap only after full success
trap - EXIT
rm -f "$backup_file"
```

---

## Step 6: `scripts/ci/tests/release_tests.sh` — Add mocks + skip flag

**All mock definitions must be placed AFTER `source "$SCRIPT_DIR/../release.sh"`** (which sources package_dmg.sh and github_release.sh), so they override the real implementations.

After existing `fake_run_build` / `run_build` override block, add:

```zsh
# Mock archive/export (no real xcodebuild)
run_archive() {
  local archive_path="$2"
  mkdir -p "$archive_path"    # simulate .xcarchive directory
}

run_export_archive() {
  local export_dir="$2"
  local log_file="$4"
  mkdir -p "$export_dir/VoxPocket.app/Contents/MacOS"
  touch "$export_dir/VoxPocket.app/Contents/MacOS/VoxPocket"
  print -- "export ok" >"$log_file"
}

# Mock DMG packaging (no hdiutil)
package_dmg() {
  local output_dir="$2"
  local dmg_name="$4"
  local final_dmg="$output_dir/$dmg_name"
  touch "$final_dmg"
  print -- "$final_dmg"
}

# Mock GitHub Release (no gh CLI, no git push)
github_release() {
  : # no-op
}
```

**Before the `release_pipeline` call, add the skip flag** to prevent `git push` from running against a fixture repo with no remote (CRITICAL fix):

```zsh
export VOX_CI_SKIP_GITHUB_RELEASE=1
release_pipeline "$repo_fixture" "main" "dev"
```

**Add DMG artifact assertion** after existing assertions:

```zsh
assert_file_exists "$repo_fixture/releases/v${next_version}/artifacts/VoxPocket-${next_version}.dmg" \
  "DMG artifact should exist"
```

---

## Step 7: `.github/workflows/release.yml` — Create

```yaml
name: release

on:
  push:
    branches: [main]

permissions:
  contents: write   # required for gh release create and git push

jobs:
  release:
    runs-on: [self-hosted, macOS, ARM64]
    timeout-minutes: 45

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0        # needed for git log (changelog) and tag detection
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Check for release loop
        id: check
        run: |
          SUBJECT="$(git log -1 --pretty=%s)"
          if echo "$SUBJECT" | grep -qE '^chore: release v'; then
            echo "skip=true" >> "$GITHUB_OUTPUT"
          else
            echo "skip=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Configure git identity
        if: steps.check.outputs.skip == 'false'
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Run release pipeline
        if: steps.check.outputs.skip == 'false'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: zsh scripts/ci/release.sh --auto

      - name: Upload release artifacts
        if: always() && steps.check.outputs.skip == 'false'
        uses: actions/upload-artifact@v4
        with:
          name: release-artifacts-${{ github.sha }}
          path: releases/
          if-no-files-found: warn
```

---

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| exportArchive output path varies by Xcode version | MEDIUM | Log `ls $export_dir` after export; adjust path if needed |
| `gh` CLI not authenticated | LOW | Verify with `gh auth status` before first run |
| Branch protection blocks release commit push | MEDIUM | GitHub Settings → Branches → add `github-actions[bot]` to bypass list |
| Keychain locked (e.g. after machine restart) | MEDIUM | Confirm Keychain is unlocked on runner; or configure codesign to "Always Allow" |

## Pre-execution Checklist
- [x] Confirm merge workflow: GitHub PR merge button ✓
- [x] `.gitignore` covers `releases/` and `.build/` ✓
- [ ] Verify `gh auth status` on runner
- [ ] Verify `security find-identity -v -p codesigning` shows Apple Development cert
- [ ] Confirm Keychain is unlocked on runner machine
- [ ] GitHub Settings → Branches → Protection rules: add `github-actions[bot]` to bypass list so release commit can be pushed directly to main
