# Local deterministic gates

Last-Reviewed: 2026-09-20

Repository-owned `.githooks/` use `core.hooksPath=.githooks`. They run shell/Python checks,
not AI reviewers or automatic repair. A failed command stops the Git operation with a nonzero
exit status; diagnose its output before retrying. The scripts anchor their working directory to
the repository, including when invoked from a subdirectory or a path containing spaces.

| Hook | Direct commands, in order |
| --- | --- |
| `pre-commit` | `bash scripts/gates/gate-precommit.sh`, `zsh scripts/docs/lint_docs_map.sh`, `zsh scripts/docs/lint_docs_freshness.sh` |
| `pre-push` | `bash scripts/gates/gate-prepush.sh` |

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
python3 -m unittest discover -s scripts/gates/tests -p 'test_local_hooks.py' -v
```
