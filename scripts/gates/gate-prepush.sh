#!/usr/bin/env bash
# gate-prepush.sh — 只放【快 + 无副作用】门禁(目标 <60s)。docs-only 短路。
# 重验证(app-target xcodebuild / 模拟器 / E2E)一律不在此 —— 由 CI required 把关。
# 由 .local-review.yml 的 push.commands 调用;可被本地 --no-verify 绕过(CI 照样拦)。
set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"

base="$(git merge-base @ origin/main 2>/dev/null || echo HEAD~1)"
changed="$(git diff --name-only "$base"..@ 2>/dev/null)"
[ -z "$changed" ] && { echo "[pre-push] 无改动"; exit 0; }

# docs-only 短路(纯文档 / hook / CI 配置 / spec)
non_doc="$(echo "$changed" | grep -vE '(\.md$|^docs/|^\.githooks/|^\.github/|^\.specify/|^scripts/gates/)' || true)"
if [ -z "$non_doc" ]; then
  echo "📝 docs/config-only — 跑 frontmatter 校验后跳过"
  python3 scripts/gates/check_frontmatter.py || exit 1
  exit 0
fi

# 门0:frontmatter 防腐(秒级、无副作用)
python3 scripts/gates/check_frontmatter.py || exit 1

# 门1:改代码必带测试 —— 改了 Sources 源码却没动任何测试 → 拦(逃生舱:commit 含 Allow-No-Tests:)
src="$(echo "$changed" | grep -E '^Packages/.*/Sources/.*\.swift$' || true)"
tst="$(echo "$changed" | grep -E '(^Packages/.*/Tests/|Tests\.swift$)' || true)"
if [ -n "$src" ] && [ -z "$tst" ]; then
  if ! git log "$base"..@ --format=%B | grep -qi '^Allow-No-Tests:'; then
    echo "❌ 改了 Sources 源码但无测试改动。补测试,或在 commit 写 Allow-No-Tests: <原因>"
    exit 1
  fi
fi

# 门2:大改动提醒(advisory,不阻塞)—— 跨 layer 时提示按 layer 拆
n="$(echo "$changed" | grep -oE '^Packages/[^/]+' | sort -u | grep -c . || true)"
[ "${n:-0}" -gt 1 ] && echo "⚠️ 本次改动涉及 $n 个 layer,考虑按 layer 拆成独立提交(AGENTS.md · 收窄范围)"

# 门3:秒级快路径 —— 只对改到的 SPM layer 跑 swift test(SPM 单包秒级,属快门禁)
layers="$(echo "$changed" | grep -oE '^Packages/[^/]+' | sort -u || true)"
while IFS= read -r L; do
  [ -z "$L" ] && continue
  [ -d "$L" ] || continue
  name="$(basename "$L")"
  echo "🧪 fast test [$name]"
  swift test --package-path "$L" >/tmp/pp-$name.log 2>&1 \
    || { echo "❌ [$name]"; tail -35 /tmp/pp-$name.log; exit 1; }
done <<< "$layers"

# ⛔ app 壳(VoxPocket/VoxPocket/**)的 xcodebuild 是分钟级重验证 —— 不在此跑,交 CI required。
if echo "$changed" | grep -qE '^VoxPocket/VoxPocket/'; then
  echo "ℹ️ 改动含 app 壳——xcodebuild 全量验证由 CI required 把关(见 pre-push 硬约束)。"
fi

# 逃生舱(默认关闭):RUN_HEAVY=1 时本地跑一次 app-target 全量验证。
if [ "${RUN_HEAVY:-0}" = "1" ]; then
  echo "🔨 RUN_HEAVY=1 — 本地跑 app-target 构建(平时由 CI 把关)"
  xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build \
    >/tmp/pp-heavy.log 2>&1 || { echo "❌ 重验证失败"; tail -40 /tmp/pp-heavy.log; exit 1; }
fi

echo "✅ pre-push 快门禁通过"
exit 0
