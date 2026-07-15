# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoxPocket is a macOS/iOS voice recording and transcription app built with SwiftUI. It captures audio, transcribes speech (default locale: `zh-Hans`), and refines text using Apple Intelligence LLM. The codebase uses Chinese comments throughout.

**Linear**: https://linear.app/tianpeili/issue/TIA-6/voxpocket

## Build & Test Commands

```bash
# Build the full Xcode project (macOS)
xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build

# Build individual packages
swift build --package-path Packages/VoxDomain
swift build --package-path Packages/VoxInfrastructure
swift build --package-path Packages/VoxApplication
swift build --package-path Packages/VoxPresentation

# Run all tests for a package
swift test --package-path Packages/VoxUITesting
swift test --package-path Packages/VoxDomain
swift test --package-path Packages/VoxApplication
swift test --package-path Packages/VoxPresentation

# Run a single test class or method
swift test --package-path Packages/VoxPresentation --filter EditorAutoStopTests
swift test --package-path Packages/VoxInfrastructure --filter TelemetryQueueTests
```

> Note: `swift test` on `VoxInfrastructure` compiles all test targets together. Pre-existing failures in one target will block others from running.

## Architecture

Five SPM packages (four in the runtime dependency chain + `VoxUITesting` standalone), in a strict layered hierarchy. Full per-layer detail lives in `docs/architecture/tech-context.md` and each `Packages/<pkg>/tech-context.md`.

```
VoxPresentation  (SwiftUI views, view models)
       ↓
VoxApplication   (use cases / business logic)
       ↓
VoxInfrastructure (TranscriptionKit · LLMKit · Persistence · PlatformAdapters · Preferences)
       ↓
LokiKit          (standalone observability / telemetry package)
       ↓
VoxDomain        (pure domain models: CoreModels, TextHistory — no external deps)

VoxUITesting     (standalone — VoxFunctionalTest snapshot tests · VoxAgentEval Claude Vision UI eval)
```

The app entry point is `VoxPocket/VoxPocket/` with `ServiceContainer` as the `@MainActor` singleton DI container.

- **Swift Tools Version**: 6.2 | **Platforms**: iOS 26+, macOS 26+
- **External dependencies**: `swift-async-algorithms` (LLMKit), `WhisperKit` (TranscriptionKit)

## Layered Agent Context

This repo is set up to be self-describing for AI agents. Before touching code, read the relevant layer's context (see `AGENTS.md` for the full Read Contract + Layer Map):

- **Constitution (iron laws)**: `.specify/memory/constitution.md` — read on every task; each layer's `red_lines` project from it.
- **Feature docs (spec)**: spec-kit (`.specify/`, `/speckit-*` skills); historical plans in `docs/plans/`.
- **Tech-context**: top-level `docs/architecture/tech-context.md` (declares `canonical_roles`) + one `Packages/<pkg>/tech-context.md` per layer, each with machine-readable frontmatter (`layer`/`depends_on`/`red_lines`/`roles`/`test`).
- **Directory index**: `AGENTS.md` is a thin router — read it first, then drill into the one relevant layer (progressive disclosure). Scope work by layer: a change crossing 2+ layers is too big — split it.
- **Gates**: `scripts/gates/` — `check_frontmatter.py` (anti-rot), `gate-precommit.sh` (incremental per-layer build/test), `gate-prepush.sh` (fast checks only, <60s). Heavy verification (`xcodebuild` app target) is CI-only (`.github/workflows/ci.yml`), not local hooks.

> **LokiKit** is an external package at `~/Development/LokiKit` (`../../../LokiKit`), not in this repo. **`VoxPocket/VoxPocket/`** is the Xcode app shell, not a layer; its `xcodebuild` verification is CI-only.

## ServiceContainer Initialization

`ServiceContainer.init()` runs synchronously on the main thread. Order matters:

1. Logger + telemetry service
2. Transcriber (selected by `LLMAppConfig.defaultTranscriberProvider`)
3. `DefaultLLMService` + macOS platform services
4. Use cases: `DefaultEditingUseCase` → `DefaultRecordingUseCase` → `DefaultTranscriptionUseCase` → `DefaultRefinementUseCase`
5. `ProxySessionUseCase` starts backed by `InMemorySessionUseCase`; call `initializePersistence()` after first UI render to hot-swap to `SwiftDataSessionUseCase`
6. **Quick recording stack** (macOS only): a fully isolated set of `quickTranscriber`, `quickRecordingUseCase`, `quickTranscriptionUseCase`, `quickRefinementUseCase` — separate from the main editor stack to prevent state pollution

## Key Patterns

- **Protocol-driven DI**: Core contracts are protocols (`RecordingUseCase`, `EditingUseCase`, `LLMService`, `TextHistoryManaging`). Default implementations prefixed with `Default`. Test doubles prefixed with `Fake` or `Mock`.
- **Concurrency**: Hybrid Combine + async/await. Thread-safe state via `Mutex<State>` from the `Synchronization` framework. `@unchecked Sendable` used for Combine compatibility. `@MainActor` on view models and UI code.
- **Streaming**: `AsyncThrowingStream` for transcription and LLM refinement events.
- **State management**: `ViewState` protocols define the view-model contract. `@Published` properties drive SwiftUI updates.
- **ProxySessionUseCase**: Wraps any `SessionUseCase` and allows swapping the backing implementation at runtime without changing call sites.

## Key Flows

- **Quick Recording** (macOS): `AppDelegate` hotkey (Fn) → `ServiceContainer.tryStartRecording()` → `WindowManager` shows floating panel → `QuickRecordingViewModel` orchestrates the full pipeline: `startRecording()` → `stopRecording()` → waits for final transcription (15s timeout) → `refineStreaming()` → `clipboardService.copy()` + `simulatePaste()` → `onComplete` callback → window hides.
- **Full Editor**: `EditorViewModel` drives recording with 2.5s silence auto-stop. Refinement streamed via `RefinementUseCase.refineStreaming()`.
- **Transcription**: `DefaultTranscriptionUseCase` bridges the `TranscriptionCoordinator` to two publishers — `liveTextPublisher` (real-time, may change) and `finalResultPublisher` (stable, emits once after stop).
- **Refinement**: `RefinementUseCase` → `LLMService` → `AppleIntelligenceProvider` → streaming `RefinementEvent` results.
- **Text History**: Patch-based undo/redo via `TextHistoryManaging` with `Checkpoint` snapshots.

## Transcriber Providers

Configured in `LLMAppConfig.defaultTranscriberProvider`:

| Provider | Description |
|---|---|
| `.appleSpeech` | Apple Speech Recognition only |
| `.localWhisperKit` | WhisperKit local model, falls back to AppleSpeech while loading |
| `.hybridWhisper` | AppleSpeech real-time preview + Azure Whisper for final quality |
| `.hybridLocalWhisper` | AppleSpeech real-time preview + local WhisperKit for final quality |

For hybrid providers, `LLMTranscriptionMerger` uses an LLM call to reconcile the two transcripts.

## Environment Variables

| Variable | Purpose |
|---|---|
| `whisperkey` | Azure Whisper API key |
| `kimikey` / `AZURE_API_KEY` | Azure AI Foundry API key |
| `LOKI_ENDPOINT` | Loki push URL (debug defaults to `http://localhost:3100/loki/api/v1/push`) |
| `LOKI_TOKEN` | Loki Bearer token for Grafana Cloud |
| `CLAUDE_API_KEY` / `ANTHROPIC_API_KEY` | Claude Vision API key for `VoxAgentEval` UI evaluation |

## Platform-Specific Code

macOS services in `PlatformAdapters`: `MacOSClipboardService`, `MacOSAccessibilityService`, `MacOSGlobalHotkeyService`, `MacOSClaudeInboxService`. Cross-platform protocols exist for each. `WindowManager` manages floating `NSPanel` windows (`FullPanel`, `QuickRecording`).

## Telemetry

`LokiTelemetryService` (from the standalone `LokiKit` package) ships events to Grafana Loki. Offline events are persisted to `~/Library/Application Support/VoxPocket/telemetry/pending/` and retried on next `flush()`. `ServiceContainer.endRecording()` triggers a flush. Local stack: `cd ~/Development/loki-telemetry-stack && docker compose up -d` → Grafana at `http://localhost:3010` (admin / telemetry), Loki at `http://localhost:3100`.

## Git Hooks

Hooks live in `.githooks/` (`core.hooksPath=.githooks`) and are managed by `local-review-skill` (v2.3.0; skill path resolved via `git config local-review.skill-path`). On commit/push/merge-to-main they run the commands in `.local-review.yml` plus Codex-based review agents (`provider: codex`, `fail_on: critical`). The `.local-review.yml` commands now also invoke the layered gate scripts (`scripts/gates/gate-precommit.sh` on commit, `scripts/gates/gate-prepush.sh` on push). If a hook blocks a commit, investigate the review output rather than bypassing with `--no-verify`.

## Task Workflow

When the user submits a problem or task, Claude MUST follow this sequence:

1. **Create or update a Linear issue** under the VoxPocket project (TIA-6) via the Linear GraphQL API (`lin_api_*` key from env or user). The issue should have a clear title and initial description.
2. **Invoke the planner agent** to expand the issue: break it into subtasks, define acceptance criteria, identify risks and dependencies. Update the Linear issue description with the enriched plan.
3. **Create sub-issues** in Linear for each subtask, all parented to the main issue.
4. **Assign subtasks to teammates** using the Agent tool in parallel where tasks are independent.

Linear API endpoint: `https://api.linear.app/graphql`
Team ID: `56d7d04f-ffb2-43f3-ad40-23fd78f551d8`
Project ID: `662a9249-b377-47c0-ad20-ccca738f4e8e`
VoxPocket parent issue: `dc74c224-59f0-4eb1-87d9-81a62a668da7` (TIA-6)

## Plan-Review Loop (MANDATORY)

When creating or modifying any implementation plan, Claude MUST follow this loop autonomously — never wait for the user to trigger review:

1. **Plan** — planner agent creates/updates the plan
2. **Review** — reviewer agent reviews the plan immediately after
3. **Revise** — if reviewer raises CRITICAL or MEDIUM issues, update the plan
4. **Re-review** — reviewer reviews again automatically
5. **Repeat** until reviewer outputs `APPROVED` with no CRITICAL issues
6. **Only then** present the final plan to the user for execution approval

This loop is Claude's responsibility. The user should never need to ask for a re-review.

## Auto-Commit Workflow

After every logical change, Claude MUST:
1. Build the affected package with `swift build` to verify no errors
2. If build passes, immediately commit to `main` with a conventional commit message — no need to ask for permission
3. Use `git add <specific files>` (never `git add -A`) and commit directly to `main`

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
