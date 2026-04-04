# VoxPocket Agent Team Blueprint

This file defines the long-term team structure for VoxPocket development.
Paste the prompt below into Claude Code to spawn the team.

---

## Role Division

| Axis | Owner | Rationale |
|------|-------|-----------|
| **Planning** | Claude (planner) | Reasoning about layered architecture, dependency order, risk |
| **Execution** | Claude (specialists via team lead) | Code generation within domain knowledge |
| **Plan Review** | Codex (`/codex:adversarial-review`) | Independent critic — must approve plan before execution starts |
| **Code Review** | Codex (`/codex:review`) | Reviews diffs after implementation, before merge |
| **Testing** | Codex (`/codex:rescue`) | Writes and runs tests as an independent quality gate |

---

## Team Roles

### Tier 1 — Claude agents (`.claude/agents/`)

Spawned as Claude Code teammates. Full reasoning, coordination, and tool access.

| Role | Agent | Responsibilities |
|------|-------|-----------------|
| **Orchestrator** | `orchestrator` | Single entry point — dispatches work, gates on Codex plan approval before executing |
| **Planner** | `planner` | Implementation plans, layer breakdown, risk assessment — revises until Codex approves |
| **PR Comment Handler** | `pr-comment-handler` | Triggered by CI on new PR comments — classifies, plans, fixes, commits, resolves comment thread |
| **Actions Monitor** | `orchestrator` (reused) | Triggered by `workflow_run` on failure — fetches logs, diagnoses root cause, applies fix, commits |

### Tier 2 — Codex review/test gates (via plugin commands)

Invoked by the orchestrator directly using the `codex-plugin-cc` plugin.
Require `/codex:setup` to be run once to verify the Codex CLI installation.

| Role | Command | Trigger |
|------|---------|---------|
| **Plan Reviewer** | `/codex:adversarial-review` | After every planner output — loop until no blockers |
| **Code Reviewer** | `/codex:review` | After implementation — before marking a task complete |
| **Test Agent** | `/codex:rescue` | Delegated test writing and execution |
| **Job Monitor** | `/codex:status` + `/codex:result` | Check background Codex tasks |

### Tier 3 — Specialist agents (`.claude/codex-agents/`)

Claude-powered domain specialists. Invoked by the team lead as `general-purpose` subagents
when the orchestrator requests them. Execution only — no planning, no reviewing.

| Role | File | Responsibilities |
|------|------|-----------------|
| **Domain Expert** | `domain-expert.md` | VoxDomain models, Patch/Checkpoint, VoxError |
| **Transcription Expert** | `transcription-expert.md` | Audio capture, AppleSpeechTranscriber, silence detection |
| **LLM Expert** | `llm-expert.md` | LLMKit, refinement pipeline, RefinementPromptBuilder |
| **Persistence Expert** | `persistence-expert.md` | SwiftData, SessionRepository, SettingsRepository |
| **Use Case Orchestrator** | `use-case-orchestrator.md` | Use cases, ServiceContainer DI, cross-layer flows |
| **UI Expert** | `ui-expert.md` | SwiftUI views, ViewModels, ViewState, Theme |
| **Platform Expert** | `platform-expert.md` | macOS/iOS adapters, hotkeys, accessibility |
| **Designer** | `designer.md` | UI/UX decisions, Liquid Glass, design system |
| **Local Reviewer Meta** | `local-reviewer-meta.md` | Review gate config, local-review-skill health (read-only auditor) |

---

## Actions Monitor Flow (CI-triggered)

Triggered by `.github/workflows/actions-monitor.yml` via `workflow_run` event.

```
Any watched workflow completes with conclusion=failure
       ↓
actions-monitor.yml fires on [self-hosted, macOS, ARM64]
       ↓
Fetch failed job logs (gh run view --log-failed, truncated 15KB)
       ↓
claude --system-prompt orchestrator.md
  → identifies root cause
  → applies fix to workflow/script files
  → swift build if Swift changed
  → git commit + push
  → post PR comment with summary
```

Watched workflows: `docs-governance`, `tests-pr`, `UI Feedback Review`, `Code Review (Codex)`

GitHub hook used: `workflow_run` event (`types: [completed]`, filtered by `conclusion == 'failure'`)

---

## PR Comment Handler Flow (CI-triggered)

Triggered by `.github/workflows/pr-comment-orchestrator.yml` via `claude` CLI.

```
PR receives comment
       ↓
pr-comment-handler classifies it
       ├── Question / Acknowledge → post reply → done
       └── Fix request / Design feedback
              ↓
           planner creates plan
              ↓
           /codex:adversarial-review loop (until no blockers)
              ↓
           specialists implement fixes
              ↓
           swift build verification (all packages)
              ↓
           /codex:review gate
              ↓
           git commit + push
              ↓
           resolve PR review thread (GraphQL)
           OR post reply comment with commit SHA
```

The handler runs on the PR branch inside the CI runner. It has full tool access
(read/edit files, bash, gh CLI) to execute the complete fix loop autonomously.

---

## Plan Review Loop (enforced by orchestrator)

```
Planner produces plan
       ↓
/codex:adversarial-review  ← Codex reviews for gaps, risks, layer violations
       ↓
Blockers found?
  YES → Planner revises → back to /codex:adversarial-review
  NO  → Plan approved → Orchestrator dispatches to specialists
```

The loop runs until Codex returns no blocker-level issues.
Minor suggestions may be noted but do not block dispatch.

---

## Post-Implementation Review Gate

After each specialist finishes a phase:

```
Specialist writes code
       ↓
/codex:review  ← Codex reviews changed files
       ↓
Critical issues?
  YES → Route back to relevant specialist for fixes → re-review
  NO  → Phase complete → proceed to next phase or mark done
```

---

## Test Gate

For every feature, the orchestrator delegates test writing to Codex:

```
/codex:rescue  "Write and run tests for <files changed>"
       ↓
/codex:status  (poll until done)
       ↓
/codex:result  (retrieve output)
       ↓
Tests pass? → proceed. Fail? → fix → re-run.
```

---

## Review Gate Requirements (enforced by `local-reviewer-meta`)

| Hook | Reviewers |
|------|-----------|
| `pre-commit` | `code-quality` + `performance` |
| `pre-merge main` | `security` + `no-microsoft-info` |
| `pre-push` | _(empty)_ |

---

## Spawn Prompt

Use this prompt in Claude Code to start the VoxPocket team (2 Claude agents only):

```
Create an agent team for VoxPocket with two Claude teammates:

1. **orchestrator** — single entry point, coordinates all work, invokes planner for complex tasks.
   Gates on Codex plan approval (/codex:adversarial-review) before dispatching execution.
   Gates on Codex code review (/codex:review) before marking implementation complete.
   Delegates test writing/running to Codex (/codex:rescue).
   Use .claude/agents/orchestrator.md.

2. **planner** — breaks down features into layered steps respecting the
   VoxDomain→VoxInfrastructure→VoxApplication→VoxPresentation hierarchy.
   Revises plan in response to Codex adversarial review feedback until approved.
   Use .claude/agents/planner.md.
```

---

## How Orchestrator Requests Specialist Work

Orchestrator messages the team lead in this format:

```
需要 [specialist-name] 处理以下任务：
- 任务描述：…
- 相关文件：Packages/…/….swift
- 上下文：（关键信息）
```

Team lead will spawn a `general-purpose` subagent with `.claude/codex-agents/<specialist>.md` as its system context.

**Orchestrator does NOT:**
- Run `codex` or bash commands for implementation work
- Spawn Claude teammates for specialist roles
- Edit files directly (delegate to team lead)
- Dispatch to specialists before Codex plan approval

---

## Local Reviewer Meta — Triggered Tasks

The `local-reviewer-meta` agent should be invoked:

- **On startup** — audit `.local-review.yml` and hooks for compliance
- **After `local-review-skill` upgrades** — check version drift and update hooks
- **When a commit is blocked unexpectedly** — diagnose misconfiguration
- **Before releases** — run smoke test of all review stages

Audit command:
```bash
LOCAL_REVIEW_WARN_ONLY=1 bash $HOME/.claude/skills/local-review-skill/assets/repo-scripts/review.sh commit
LOCAL_REVIEW_WARN_ONLY=1 bash $HOME/.claude/skills/local-review-skill/assets/repo-scripts/review.sh merge_to_main
```
