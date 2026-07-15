#!/usr/bin/env bash
# gate-precommit.sh — 增量 layer 级发现(秒级)。全量与重验证在 CI required。
# 只对暂存改动涉及的 Packages/<layer> 跑 swift build + swift test,并跑 frontmatter 防腐。
# 由 .local-review.yml 的 commit.commands 调用;可被本地 --no-verify 绕过(CI 照样拦)。
set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"

staged="$(git diff --cached --name-only --diff-filter=ACMR)"
[ -z "$staged" ] && exit 0

# frontmatter 一改就校验(秒级、无副作用)
if echo "$staged" | grep -qE '(tech-context\.md|Package\.swift|scripts/gates/check_frontmatter\.py)'; then
  echo "[pre-commit] frontmatter 防腐校验"
  python3 scripts/gates/check_frontmatter.py || exit 1
fi

# 映射到受影响的仓库内 layer(Packages/<name>)
layers="$(echo "$staged" | grep -oE '^Packages/[^/]+' | sort -u)"
fail=0
while IFS= read -r L; do
  [ -z "$L" ] && continue
  [ -d "$L" ] || continue
  name="$(basename "$L")"
  echo "[pre-commit] build+test [$name]"
  swift build --package-path "$L" >/tmp/pc-$name.log 2>&1 \
    || { echo "❌ build [$name]"; tail -25 /tmp/pc-$name.log; fail=1; continue; }
  swift test --package-path "$L" >>/tmp/pc-$name.log 2>&1 \
    || { echo "❌ test [$name]"; tail -35 /tmp/pc-$name.log; fail=1; }
done <<< "$layers"

# 顶层 app 壳(VoxPocket/VoxPocket/**)是分钟级 xcodebuild —— 不在此跑,交 CI required。
if echo "$staged" | grep -qE '^VoxPocket/VoxPocket/'; then
  echo "[pre-commit] ℹ️ 改动含 app 壳(VoxPocket/VoxPocket/**)——其 xcodebuild 全量验证归 CI,不在本地阻塞。"
fi

[ "$fail" -eq 0 ] || { echo "修复后重新 commit(勿 --no-verify;CI 照样拦)"; exit 1; }
exit 0
