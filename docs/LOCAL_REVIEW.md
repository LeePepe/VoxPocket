<!-- managed-by: local-review-skill -->
<!-- local-review-skill version: 2.1.0 -->

# Local Review

This repository uses `local-review-skill` to enforce local review gates without a remote code hosting platform.

## Installed Files

- `.githooks/pre-commit`
- `.githooks/pre-push`
- `.githooks/pre-merge-commit`
- `scripts/review.sh`
- `scripts/merge-to-main.sh`
- `.local-review.yml`

## How It Works

- `pre-commit` runs the `commit` stage
- `pre-push` runs the `push` stage
- `pre-merge-commit` runs the `merge_to_main` stage only when the current branch is `main`
- `scripts/merge-to-main.sh` gives you an explicit wrapper for merge-to-main workflows

All stage commands and reviewer config come from `.local-review.yml`.

## Configure Shell Commands

Edit `.local-review.yml`:

```yaml
commit:
  - "make lint"

push:
  - "make test"

merge_to_main:
  - "make test"
  - "make smoke"
```

## AI Reviewers (Built-in Subagents)

Three built-in reviewer agents run in parallel. Which types run depends on the stage:

| Stage | Reviewers |
|-------|-----------|
| `commit` | **performance**, **code_quality** |
| `push` | **security**, **performance**, **code_quality** |
| `merge_to_main` | **security** |

- **security** — secrets, injection, auth bypass, permissions
- **performance** — algorithmic complexity, I/O in loops, resource leaks
- **code_quality** — naming, responsibilities, comments, dead code

Each reviewer outputs `[CRITICAL]`, `[HIGH]`, `[MEDIUM]`, or `[LOW]` tagged findings and a
`VERDICT: PASS | WARN | FAIL` line. The script aggregates all findings and reports the worst verdict.

Configure the provider and model in `.local-review.yml`:

```yaml
provider: codex              # codex (default) | claude | auto
model: gpt-5.4-codex     # optional model override
fail_on: high                # critical | high | medium | low | never  (default: high)
auto_fix: true               # attempt auto-repair on FAIL (default: true)
max_fix_attempts: 3          # max repair iterations (default: 3)
```

To disable or tune individual reviewer types (`reviewers:` is nested under the stage name):

```yaml
push:
  reviewers:
    - type: security
      enabled: true
      model: gpt-5.4-codex
    - type: performance
      enabled: false
    - type: code_quality
      enabled: true
```

### Severity Levels

| Level | Meaning |
|-------|---------|
| `CRITICAL` | Security vulnerability, data loss risk, clear bug |
| `HIGH` | Logic error, serious performance issue, project standard violation |
| `MEDIUM` | Code quality, readability, minor standard violation |
| `LOW` | Style suggestion, optional improvement |

Set `fail_on` to the lowest severity that should block a commit/push.
For example, `fail_on: high` blocks on `CRITICAL` and `HIGH` findings.

When reviewers finish, a desktop notification is sent automatically:
- **macOS**: system notification (Glass sound on pass, Basso on failure)
- **Linux**: `notify-send` if available, otherwise terminal bell

Disable notifications with `notify: false` in `.local-review.yml`.

## Global Config (All Repos)

Create `~/.config/local-review/config.yml` to apply checks to every repo automatically:

Per-repo config is **merged on top** of the global config (global commands run first).
It accepts the same keys as `.local-review.yml`; see `references/config-schema.md` for the full schema.

## Environment Variables

| Variable | Effect |
|----------|--------|
| `LOCAL_REVIEW_SKIP=1` | Skip all checks and exit 0 |
| `LOCAL_REVIEW_WARN_ONLY=1` | Print findings but never block the git operation |
| `LOCAL_REVIEW_AUTO_FIX=0` | Disable automatic fix loop |
| `LOCAL_REVIEW_AUTO_FIX=1` | Enable automatic fix loop (overrides config) |
| `LOCAL_REVIEW_MAX_FIX_ATTEMPTS=N` | Override maximum fix iterations |
| `LOCAL_REVIEW_PROVIDER=codex\|claude\|auto` | Override AI provider |
| `LOCAL_REVIEW_MODEL=<name>` | Override model name |

## Hooks

This setup configures:

```bash
git config core.hooksPath .githooks
```

If hooks stop firing, verify:

```bash
git config --get core.hooksPath
```
