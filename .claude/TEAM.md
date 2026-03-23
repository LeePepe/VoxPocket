# VoxPocket Agent Team Blueprint

This file defines the long-term team structure for VoxPocket development.
Paste the prompt below into Claude Code to spawn the team.

---

## Team Roles

### Tier 1 — Claude agents (`.claude/agents/`)

Spawned as Claude Code teammates. Full reasoning, coordination, and tool access.

| Role | Agent | Responsibilities |
|------|-------|-----------------|
| **Orchestrator** | `orchestrator` | Single entry point, dispatches work, synthesizes results |
| **Planner** | `planner` | Implementation plans, layer breakdown, risk assessment |

### Tier 2 — Specialist agents (`.claude/codex-agents/`)

System prompt definitions for focused specialist roles. Invoked by the team lead as subagents when orchestrator requests them. Codex CLI is not available — the team lead spawns a `general-purpose` subagent with the specialist's `.md` as context.

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
   When specialist work is needed, message the team lead with the task and relevant context —
   the team lead will spawn the appropriate subagent. Use .claude/agents/orchestrator.md.

2. **planner** — breaks down features into layered steps respecting the
   VoxDomain→VoxInfrastructure→VoxApplication→VoxPresentation hierarchy.
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

---

## Local Reviewer Meta — Triggered Tasks

The `local-reviewer-meta` agent should be invoked:

- **On startup** — audit `.local-review.yml` and hooks for compliance
- **After `local-review-skill` upgrades** — check version drift and update hooks
- **When a commit is blocked unexpectedly** — diagnose misconfiguration
- **Before releases** — run smoke test of all review stages

Audit command:
```bash
LOCAL_REVIEW_WARN_ONLY=1 bash /Users/tianpli/.claude/skills/local-review-skill/assets/repo-scripts/review.sh commit
LOCAL_REVIEW_WARN_ONLY=1 bash /Users/tianpli/.claude/skills/local-review-skill/assets/repo-scripts/review.sh merge_to_main
```
