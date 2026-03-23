# VoxPocket Agent Team Blueprint

This file defines the long-term team structure for VoxPocket development.
Paste the prompt below into Claude Code to spawn the team.

---

## Team Roles

| Role | Agent | Responsibilities |
|------|-------|-----------------|
| **Orchestrator** | `orchestrator` | Single entry point, dispatches work, synthesizes results |
| **Planner** | `planner` | Implementation plans, layer breakdown, risk assessment |
| **Domain Expert** | `domain-expert` | VoxDomain models, Patch/Checkpoint, VoxError |
| **Transcription Expert** | `transcription-expert` | Audio capture, AppleSpeechTranscriber, silence detection |
| **LLM Expert** | `llm-expert` | LLMKit, refinement pipeline, RefinementPromptBuilder |
| **Persistence Expert** | `persistence-expert` | SwiftData, SessionRepository, SettingsRepository |
| **Use Case Orchestrator** | `use-case-orchestrator` | Use cases, ServiceContainer DI, cross-layer flows |
| **UI Expert** | `ui-expert` | SwiftUI views, ViewModels, ViewState, Theme |
| **Platform Expert** | `platform-expert` | macOS/iOS adapters, hotkeys, accessibility |
| **Designer** | `designer` | UI/UX decisions, Liquid Glass, design system |
| **Local Reviewer Meta** | `local-reviewer-meta` | Review gate config, local-review-skill health |

---

## Review Gate Requirements (enforced by `local-reviewer-meta`)

| Hook | Reviewers |
|------|-----------|
| `pre-commit` | `code-quality` + `performance` |
| `pre-merge main` | `security` + `no-microsoft-info` |
| `pre-push` | _(empty)_ |

---

## Spawn Prompt

Use this prompt in Claude Code to start the VoxPocket team:

```
Create an agent team for VoxPocket with these teammates:

1. **orchestrator** — entry point, coordinates all work, synthesizes results. Use agent definition at .claude/agents/orchestrator.md.

2. **planner** — breaks down features into layered steps respecting the VoxDomain→VoxInfrastructure→VoxApplication→VoxPresentation hierarchy. Use .claude/agents/planner.md.

3. **domain-expert** — owns VoxDomain models, Patch mechanism, TextHistory. Use .claude/agents/domain-expert.md.

4. **transcription-expert** — owns audio capture and AppleSpeechTranscriber. Use .claude/agents/transcription-expert.md.

5. **llm-expert** — owns LLMKit, refinement pipeline, intent recognition. Use .claude/agents/llm-expert.md.

6. **persistence-expert** — owns SwiftData, SessionRepository, SettingsRepository. Use .claude/agents/persistence-expert.md.

7. **use-case-orchestrator** — owns use cases and ServiceContainer wiring. Use .claude/agents/use-case-orchestrator.md.

8. **ui-expert** — owns SwiftUI views and ViewModels. Use .claude/agents/ui-expert.md.

9. **platform-expert** — owns macOS/iOS platform adapters. Use .claude/agents/platform-expert.md.

10. **designer** — owns UI/UX design decisions and Liquid Glass design system. Use .claude/agents/designer.md.

11. **local-reviewer-meta** — monitors and enforces the local-review-skill configuration. Requirements: pre-commit runs code-quality+performance; pre-merge main runs security+no-microsoft-info. Use .claude/agents/local-reviewer-meta.md.

Have the orchestrator receive tasks and route to the appropriate specialist. The local-reviewer-meta should audit .local-review.yml on startup and report any drift from requirements.
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
