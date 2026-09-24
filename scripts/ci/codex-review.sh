#!/usr/bin/env bash
# VoxPocket 自动 code review（codex）—— 在 self-hosted runner 上用本地 `codex` CLI 跑。
#
# 旧 VoxPocket 自有 review 入口；required gate 现由 shared-ci codex-review.yml 调用 review-raven.py。
# 由 .github/workflows/codex-review-target.yml 的 trusted-base job 调用。
# **安全边界在 workflow YAML 的 job-level `if`**(来自 base 分支、fork 改不到):
# 只有同仓库分支 PR 才会到达这里;fork PR 由另一个 job 处理,PR 代码不在本机执行。
# 本脚本不自行判 fork —— 那个判断放在被 PR 篡改的脚本里是不可信的。
#
# 设计成确定性门:
#   - 无 blocker           → 贴一条 sticky comment,exit 0(check 绿)
#   - 有 blocker(P0/严重) → 更新 sticky comment,exit 1(check 红 → 挡 auto-merge)
#   - 任何工具异常          → exit 1(fail closed,宁可卡住也不放行未审的 diff)
#
# 依赖:git, gh(runner 环境自带 GITHUB_TOKEN), jq, python3(3.11+), codex, 本地 Raven。
# 需要的环境变量(workflow 注入):
#   PR_NUMBER, BASE_SHA, HEAD_SHA, BASE_REPO, GH_TOKEN
#
# 连接参数来自日常 ~/.codex/config.toml 的 Raven provider；凭据仅由已有环境提供。
# 审查仍使用独立 CODEX_HOME(默认 ~/.codex-review)，不继承日常模型、hooks 或 MCP。
# 缺少 Raven 配置/环境时失败关闭，不回退到直连 OpenAI，不读取或复制凭据文件。

set -uo pipefail

# 独立 CODEX_HOME:review 门专用,不碰用户日常的 ~/.codex(raven/cmux)。
export CODEX_HOME="${CODEX_REVIEW_HOME:-$HOME/.codex-review}"
# 保留标准 codex 二进制；下方 launcher 显式接入 Raven，不依赖 PATH 中的日常 shim。
CODEX_BIN="${CODEX_BIN:-/opt/homebrew/bin/codex}"
command -v "$CODEX_BIN" >/dev/null 2>&1 || CODEX_BIN="codex"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

: "${PR_NUMBER:?}"; : "${BASE_SHA:?}"; : "${HEAD_SHA:?}"; : "${BASE_REPO:?}"

# 先验证 provider / 环境 / binary；不调用模型，也不把 setup PASS 当作 review PASS。
if ! python3 "$REPO_ROOT/scripts/ci/review-raven.py" --check-setup "$CODEX_BIN"; then
    echo "[codex-review] setup failed before review; prepare runner environment before retry" >&2
    exit 1
fi

STICKY="<!-- voxpocket-codex-review -->"

post_sticky() {
    # 维护同一条 sticky 评论(避免每次 synchronize 刷屏)。$1=正文。
    # 用 REST 直接按 marker 找本 bot 已发的那条并 PATCH;没有则新建。
    local body="$1" id
    id="$(gh api "repos/$BASE_REPO/issues/$PR_NUMBER/comments" --paginate \
        --jq "[.[] | select(.body | contains(\"$STICKY\"))] | last | .id" 2>/dev/null || true)"
    if [ -n "$id" ] && [ "$id" != "null" ]; then
        gh api -X PATCH "repos/$BASE_REPO/issues/comments/$id" -f body="$body" >/dev/null \
            && return 0
    fi
    gh pr comment "$PR_NUMBER" --body "$body" >/dev/null
}

# ---- 取 diff ------------------------------------------------------------
# 工作树是 checkout base 的,PR 的 HEAD 对象只能靠这次 fetch 才存在。因此 fetch
# 失败不能吞掉——否则 HEAD 取不到 → diff 为空 → 被误判成"无 diff pass",一次网络
# 抖动就能让 review 门在未审 diff 的情况下放绿灯(fail-open)。这里 fail-closed:
# fetch 失败、或 fetch 后 BASE/HEAD 对象仍缺失,一律 exit 1(宁可卡住不放行)。
if ! git fetch --no-tags --depth=100 origin "$BASE_SHA" "$HEAD_SHA" 2>/tmp/codex-fetch.err; then
    echo "[codex-review] ❌ git fetch 失败,无法取 PR diff"; cat /tmp/codex-fetch.err >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能取到 PR diff(git fetch 失败)。为安全起见 **暂不放行**,请重跑。"
    exit 1
fi
if ! git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null || ! git cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
    echo "[codex-review] ❌ fetch 后 BASE/HEAD 对象仍缺失,无法可靠取 diff"
    post_sticky "$STICKY
⚠️ 自动 review 无法取到完整 PR 提交对象。为安全起见 **暂不放行**,请重跑。"
    exit 1
fi
DIFF="$(git diff "$BASE_SHA...$HEAD_SHA" 2>/dev/null || git diff "$BASE_SHA..$HEAD_SHA")"
CHANGED="$(git diff --name-only "$BASE_SHA...$HEAD_SHA" 2>/dev/null || git diff --name-only "$BASE_SHA..$HEAD_SHA")"

# 此处 DIFF 为空 = BASE/HEAD 对象都在但两者间确无差异(罕见但合法,如仅改 commit
# message 的空 diff PR)。既然对象已确认存在,空 diff 是真·无改动,可安全 pass。
if [ -z "$DIFF" ]; then
    post_sticky "$STICKY
✅ 无代码 diff,自动 review 通过。"
    echo "[codex-review] empty diff (对象已验证存在); pass"
    exit 0
fi

# diff 过大时截断(保护 CLI 上下文;截断本身在 prompt 里声明)。
MAX_BYTES=200000
TRUNCATED=""
if [ "$(printf %s "$DIFF" | wc -c)" -gt "$MAX_BYTES" ]; then
    DIFF="$(printf %s "$DIFF" | head -c "$MAX_BYTES")"
    TRUNCATED="（diff 已截断至 ${MAX_BYTES} 字节；未覆盖部分请人工留意）"
fi

# ---- verdict schema -----------------------------------------------------
# codex --output-schema 要求 schema 放在文件里；写到临时文件并在退出时清理。
SCHEMA_FILE="$(mktemp -t codex-review-schema.XXXXXX.json)"
OUT_FILE="$(mktemp -t codex-review-out.XXXXXX.json)"
ERR_FILE="$(mktemp -t codex-review-err.XXXXXX.log)"
cleanup() { rm -f "$SCHEMA_FILE" "$OUT_FILE" "$ERR_FILE"; }
trap cleanup EXIT

cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{
  "type":"object","additionalProperties":false,
  "required":["verdict","summary","blockers","notes"],
  "properties":{
    "verdict":{"type":"string","enum":["pass","changes"]},
    "summary":{"type":"string"},
    "blockers":{"type":"array","items":{"type":"object","additionalProperties":false,
      "required":["file","line","severity","why"],
      "properties":{"file":{"type":"string"},"line":{"type":["integer","null"]},
        "severity":{"type":"string","enum":["critical","high"]},"why":{"type":"string"}}}},
    "notes":{"type":"array","items":{"type":"object","additionalProperties":false,
      "required":["file","line","note"],
      "properties":{"file":{"type":"string"},"line":{"type":["integer","null"]},"note":{"type":"string"}}}}
  }
}
SCHEMA_EOF

# ---- review prompt ------------------------------------------------------
# 维度依据同一套仓库宪法。
# Trusted Markdown is rendered as data: no shell evaluation or recursive substitution.
if ! PROMPT="$(CHANGED="$CHANGED" TRUNCATED="$TRUNCATED" DIFF="$DIFF" \
    python3 "$REPO_ROOT/scripts/ci/render-review-prompt.py" "$REPO_ROOT/scripts/ci/review-prompt.md")"; then
    echo "[codex-review] prompt render failed; refusing unreviewed diff" >&2
    exit 1
fi

echo "[codex-review] running codex on PR #$PR_NUMBER ($(printf '%s\n' "$CHANGED" | grep -c . | tr -d ' ') files)..."

# codex exec：非交互、结构化输出到 --output-last-message 文件。
# --skip-git-repo-check：checkout 目录是 detached HEAD，跳过 git 仓库信任检查。
# hooks / MCP / 沙箱 / effort 均由独立 CODEX_HOME 的 config.toml 固定；这里只
# 再显式钉一遍关键项，防 config 缺失时回退到危险默认。
python3 "$REPO_ROOT/scripts/ci/review-raven.py" "$CODEX_BIN" \
    --output-schema "$SCHEMA_FILE" \
    -o "$OUT_FILE" \
    --skip-git-repo-check \
    -c sandbox_mode=read-only \
    -c approval_policy=never \
    "$PROMPT" >/dev/null 2>"$ERR_FILE"
CLI_RC=$?

RAW="$(cat "$OUT_FILE" 2>/dev/null)"

if [ "$CLI_RC" -ne 0 ] || [ -z "$RAW" ]; then
    echo "[codex-review] ❌ codex CLI 失败 (rc=$CLI_RC)"; tail -c 2000 "$ERR_FILE" >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能完成(codex CLI 异常)。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

# codex -o 直接落最终 JSON 对象；若被包了额外文本则尝试提取首个 JSON 块兜底。
VERDICT_JSON="$(printf %s "$RAW" | jq -c '.' 2>/dev/null)"
if [ -z "$VERDICT_JSON" ] || [ "$VERDICT_JSON" = "null" ]; then
    VERDICT_JSON="$(printf %s "$RAW" | sed -n '/{/,/}/p' | jq -c '.' 2>/dev/null | head -1)"
fi
if [ -z "$VERDICT_JSON" ] || [ "$VERDICT_JSON" = "null" ]; then
    echo "[codex-review] ❌ 无法解析 verdict"; printf %s "$RAW" | head -c 2000 >&2
    post_sticky "$STICKY
⚠️ 自动 review 输出无法解析。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

VERDICT="$(printf %s "$VERDICT_JSON" | jq -r '.verdict')"
SUMMARY="$(printf %s "$VERDICT_JSON" | jq -r '.summary')"
N_BLOCK="$(printf %s "$VERDICT_JSON" | jq -r '.blockers | length')"

# 渲染评论正文
render() {
    printf '%s\n' "$STICKY"
    if [ "$VERDICT" = "changes" ]; then
        printf '## 🔴 codex review:需要修改（%s 个阻塞项）\n\n' "$N_BLOCK"
    else
        printf '## ✅ codex review:通过\n\n'
    fi
    printf '%s\n' "$SUMMARY"
    if [ "$N_BLOCK" -gt 0 ]; then
        printf '\n### 阻塞项\n'
        printf %s "$VERDICT_JSON" | jq -r \
            '.blockers[] | "- **\(.severity)** `\(.file)\(if .line then ":\(.line)" else "" end)` — \(.why)"'
    fi
    local n_notes
    n_notes="$(printf %s "$VERDICT_JSON" | jq -r '.notes | length')"
    if [ "$n_notes" -gt 0 ]; then
        printf '\n### 建议（不阻塞）\n'
        printf %s "$VERDICT_JSON" | jq -r \
            '.notes[] | "- `\(.file)\(if .line then ":\(.line)" else "" end)` — \(.note)"'
    fi
    printf '\n\n<sub>由本地 codex 自动生成。critical/high = 阻塞合并。</sub>\n'
}
BODY="$(render)"

if [ "$VERDICT" = "changes" ] && [ "$N_BLOCK" -gt 0 ]; then
    post_sticky "$BODY"
    echo "[codex-review] ❌ verdict=changes, blockers=$N_BLOCK → exit 1"
    exit 1
fi

post_sticky "$BODY"
echo "[codex-review] ✅ verdict=pass → exit 0"
exit 0
