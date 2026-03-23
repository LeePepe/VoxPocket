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

### Tier 2 — Codex agents (`.claude/codex-agents/`)

Invoked via `codex -q "$(cat .claude/codex-agents/<file>)\n\nTask: ..."`. Focused, cost-efficient specialists.

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

1. **orchestrator** — single entry point, coordinates all work, invokes planner for complex tasks, calls codex specialists via bash for implementation. Use .claude/agents/orchestrator.md.

2. **planner** — breaks down features into layered steps respecting the VoxDomain→VoxInfrastructure→VoxApplication→VoxPresentation hierarchy. Use .claude/agents/planner.md.

Specialist work (domain, ui, persistence, llm, platform, etc.) is handled by codex agents in .claude/codex-agents/ invoked via bash by the orchestrator. Do NOT spawn Claude teammates for those roles.
```

## Invoking Codex Specialists

From the orchestrator or directly from the team lead:

```bash
# Single specialist
codex -q "$(cat .claude/codex-agents/domain-expert.md)

Task: Add a new field 'exportedAt: Date?' to the Session model.
Context: $(cat Packages/VoxDomain/Sources/VoxDomain/CoreModels/Session.swift)"

# Parallel specialists
codex -q "$(cat .claude/codex-agents/ui-expert.md)

Task: ..." > /tmp/ui_result.txt &

codex -q "$(cat .claude/codex-agents/llm-expert.md)

Task: ..." > /tmp/llm_result.txt &

wait && cat /tmp/ui_result.txt /tmp/llm_result.txt
```

---

## Local Reviewer Meta — Triggered Tasks

The `local-reviewer-meta` agent should be invoked:

- **On startup** — audit `.local-review.yml` and hooks for compliance
- **After `local-review-skill` upgrades** — check version drift and update hooks
- **When a commit is blocked unexpectedly** — diagnose misconfiguration
- **Before releases** — run smoke test of all review stages

Audit command:
```bash
LOCAL_REVIEW_WARN_ONLY=1 bash scripts/review.sh commit
LOCAL_REVIEW_WARN_ONLY=1 bash scripts/review.sh merge_to_main
```
