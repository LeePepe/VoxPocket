# Local deterministic gates

Last-Reviewed: 2026-09-24

Repository-owned `.githooks/` use `core.hooksPath=.githooks`. They run shell/Python checks,
not AI reviewers or automatic repair. A failed command stops the Git operation with a nonzero
exit status; diagnose its output before retrying. The scripts anchor their working directory to
the repository, including when invoked from a subdirectory or a path containing spaces.

| Hook | Direct commands, in order |
| --- | --- |
| `pre-commit` | `bash scripts/gates/gate-precommit.sh`, `zsh scripts/docs/lint_docs_map.sh`, `zsh scripts/docs/lint_docs_freshness.sh` |
| `pre-push` | `scripts/verify` (changed mode) |

`scripts/verify` is the single entry shared with CI. It fetches the shared-ci resolver at the SHA
pinned in `AGENTS.md` into `.shared-ci/` (gitignored), runs the contract audit and workflow-lint,
then `bash scripts/gates/gate-prepush.sh` (unchanged checks below), then the resolver-selected
gates of changed layers outside `Packages/` (for example `VoxPocketApp`). CI runs
`scripts/verify --all`, `--layer <name>` (the `SPM <pkg>` and `App target` checks) and
`--policy` (`Lint & policy`). External packages are fetched at pinned SHAs by
`scripts/ci/fetch-external-deps.sh`.

The commit gate uses staged files. The push gate uses committed `HEAD` changes since the
merge-base with `origin/main`, even when the working tree is clean. The hook checks Git's
actual push input and accepts branch updates only when their candidate is the current `HEAD`.
For another branch or tag, it stops instead of checking the wrong candidate; switch to the
branch being delivered and use the normal branch → PR workflow. Remote-reference deletion
does not introduce a new candidate. A missing/unreadable `origin/main` baseline stops the gate;
refresh the verified remote before retrying. Direct diagnostic invocation of the gate script
checks `HEAD` only and is not evidence for another pushed candidate.

Layer checks, frontmatter validation, private-config guards, changed-source/test policy and
documentation checks keep their existing rules. App builds and required AI review remain in
CI; local checks cannot replace server-side gates. Internal AI Reviewer approval is unchanged.

## Retirement record

On 2026-09-20 the duplicate `local-review-skill` integration was retired: its configuration,
merge wrapper, merge hook, meta-agent definitions and installation instructions were removed.
The deterministic commands previously declared in that configuration now run directly.
Historical plans mentioning the retired configuration describe the old arrangement only.

Regression checks (isolated Git fixtures; no AI, network, or product build):

```bash
python3 -m unittest discover -s scripts/gates/tests -p 'test_local_hooks.py' -v   # hooks + scripts/verify wiring
```

## Actions Raven bootstrap (runner operations)

The required `codex-review-target / codex-review` gate is independent of local hooks. Its launcher reads only
Raven connection metadata from `CODEX_RAVEN_CONFIG` (default `~/.codex/config.toml`): an explicit
Raven provider, loopback endpoint with a port, Responses API, and no OpenAI account auth.
It accepts only the configured `OPENAI_API_KEY` or `RAVEN_API_KEY` environment name. It never
loads `auth.json`, copies credentials, evaluates shell configuration, or falls back to OpenAI.

Two auth layers must be prepared separately by the Owner: the runner's Raven client key permits
access to Raven; Raven's own Copilot authentication permits upstream model use. A valid client
key does not prove the upstream login is ready. Terminal environment variables do not imply
that a launchd/noninteractive runner has them. Provision the private environment source and
narrow runner-startup wiring outside this repository, owner-only, without sourcing the full
interactive shell configuration. Keep key values environment-only in the review invocation;
never place them in CLI arguments, logs, GitHub comments, repository files or config examples.
Credential creation/rotation and any runner/Raven service restart remain Owner operations.

`CODEX_REVIEW_HOME` is the only review-home override; otherwise `~/.codex-review` is used even
when daily `CODEX_HOME` is inherited. The launcher rejects the daily provider-config directory
as a review home (including symlink aliases). The Owner must retain the existing review-only
model/effort and no-hooks/no-MCP/read-only/never-approval profile there; do not copy the full
daily config. This change neither provisions nor edits the host profile or credentials.

Setup-only diagnostic, from the trusted checkout in the intended runner environment:

```bash
python3 scripts/ci/review-raven.py --check-setup /opt/homebrew/bin/codex
```

This checks provider metadata, required environment presence, binary availability and home
separation only. It does not read credential files, inspect the profile contents, start Codex,
contact Raven, or verify upstream auth. Setup PASS is not runtime/model, review-verdict or merge
PASS. The review script runs this check before fetching/rendering the diff; setup failures have
sanitized diagnostics and stop without a model call. Fix environment readiness before a targeted
retry, not by repeatedly rerunning a missing-key failure. A later model failure, verdict, required
check result and merge outcome are distinct stages and must be reported separately.

Bootstrap order matters: `pull_request_target` checks out the trusted **base** scripts and reads
the PR diff as data. A candidate launcher change cannot repair its own old-base execution path.
Prepare the Owner-managed runner environment for the current trusted base first, then perform
an authorized targeted review retry and the normal required-check/merge flow. Never execute PR
head bootstrap code to bypass that boundary. This candidate does not change required/advisory
status, prompts, auto-merge, paused workflows or release settings.

Offline regressions (synthetic environment/metadata; no live model or host configuration change):

```bash
python3 -m unittest discover -s scripts/ci/tests -p 'test_review_*.py' -v
```
