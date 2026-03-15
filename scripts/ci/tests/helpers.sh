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

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local message="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$message (missing=$needle)"
}

assert_file_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "expected file to exist: $path"
}

make_temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/voxpocket-ci-test.XXXXXX"
}

make_fixture_project() {
  local destination="$1"
  cat >"$destination" <<'EOF'
MARKETING_VERSION = 1.0;
CURRENT_PROJECT_VERSION = 1;
MARKETING_VERSION = 1.0;
CURRENT_PROJECT_VERSION = 1;
EOF
}

init_fixture_repo() {
  local repo_root="$1"

  git -C "$repo_root" init -q
  git -C "$repo_root" config user.name "VoxPocket Tests"
  git -C "$repo_root" config user.email "tests@example.com"

  cat >"$repo_root/README.md" <<'EOF'
# Fixture Repo
EOF

  git -C "$repo_root" add README.md
  git -C "$repo_root" commit -q -m "docs: initial"
  git -C "$repo_root" tag v1.0.0

  cat >"$repo_root/feature.txt" <<'EOF'
feature
EOF
  git -C "$repo_root" add feature.txt
  git -C "$repo_root" commit -q -m "feat: sample feature"

  cat >"$repo_root/fix.txt" <<'EOF'
fix
EOF
  git -C "$repo_root" add fix.txt
  git -C "$repo_root" commit -q -m "fix: sample fix"

  cat >"$repo_root/chore.txt" <<'EOF'
chore
EOF
  git -C "$repo_root" add chore.txt
  git -C "$repo_root" commit -q -m "docs: sample docs"
}

make_release_fixture_repo() {
  local repo_root="$1"

  git -C "$repo_root" init -q
  git -C "$repo_root" config user.name "VoxPocket Tests"
  git -C "$repo_root" config user.email "tests@example.com"
  mkdir -p "$repo_root/VoxPocket/VoxPocket.xcodeproj"

  cat >"$repo_root/VoxPocket/VoxPocket.xcodeproj/project.pbxproj" <<'EOF'
MARKETING_VERSION = 1.3.2;
CURRENT_PROJECT_VERSION = 41;
MARKETING_VERSION = 1.3.2;
CURRENT_PROJECT_VERSION = 41;
EOF

  cat >"$repo_root/README.md" <<'EOF'
# Fixture Repo
EOF

  git -C "$repo_root" add .
  git -C "$repo_root" commit -q -m "docs: initial"
  git -C "$repo_root" tag v1.3.2

  cat >"$repo_root/feature.txt" <<'EOF'
feature
EOF
  git -C "$repo_root" add feature.txt
  git -C "$repo_root" commit -q -m "feat: sample feature"
}
