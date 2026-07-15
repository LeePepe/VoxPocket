# VoxPocket Constitution

> The iron laws of this codebase. Every task must read this first and confirm it does not
> cross a red line. These rules are near-invariant; they change only by deliberate amendment
> (see Governance). Each layer's `tech-context.md` frontmatter `red_lines` is a **projection**
> of the rules here onto that layer — layers never invent independent rules.

## Core Principles

### I. Immutability (NON-NEGOTIABLE)
Never mutate shared or passed-in objects in place. Produce a new value and return it.
Domain models (`CoreModels`, `TextHistory`) are value types; updates return copies
(patch-based history via `Checkpoint`, not in-place edits). Rationale: immutable data
eliminates hidden side effects and makes the hybrid Combine + async/await concurrency safe.

### II. Layered Dependency Direction (NON-NEGOTIABLE)
Dependencies flow one way only, and never reverse:

```
VoxPresentation → VoxApplication → VoxInfrastructure → LokiKit → VoxDomain
```

- `VoxDomain` takes **no external dependencies** and imports no other local layer.
- No layer may import a layer above it. A lower layer reaching upward is a red line, not a refactor.
- This applies at two axes: **inter-layer** (package `depends_on`) and **intra-layer**
  (class stereotype `roles`, see the top-level tech-context `canonical_roles`). Lower role
  must not depend on higher role within a package either.

### III. Concurrency Safety (NON-NEGOTIABLE)
- Shared mutable state is guarded by `Mutex<State>` (from `Synchronization`), never by ad-hoc locks
  or unguarded `var`.
- View models and all UI code are `@MainActor`.
- `@unchecked Sendable` is permitted **only** for Combine bridging and must be justified at the
  declaration; never as a shortcut to silence the compiler.
- No blocking calls (`Thread.sleep`, synchronous I/O, blocking waits) on the main thread — ever.
- Streaming uses `AsyncThrowingStream`; errors propagate, never silently dropped.

### IV. Privacy of Voice & Text (NON-NEGOTIABLE)
Recorded audio, live/final transcripts, and refined user text are sensitive user data.
- Never write transcript content, audio buffers, or refined text into logs or telemetry payloads.
  Telemetry carries metrics only (durations, counts, source labels, session IDs) — never content.
- Never persist user content outside the app's own sandbox
  (`~/Library/Application Support/VoxPocket/`).

### V. Secrets & External-Vendor Hygiene (NON-NEGOTIABLE)
- No hardcoded secrets, API keys, or tokens in source. All keys come from environment variables
  (`whisperkey`, `kimikey`/`AZURE_API_KEY`, `LOKI_TOKEN`, `CLAUDE_API_KEY`/`ANTHROPIC_API_KEY`).
  Validate required keys are present at startup; fail fast with a clear message.
- No Microsoft-specific identifiers in committed code: no Azure resource IDs, tenant IDs,
  Microsoft account references, Windows registry paths, OneDrive/SharePoint/Teams fields,
  or Microsoft copyright notices. Endpoints must come from config/env, not literals.

### VI. Input Validation at Boundaries
Validate all external data (API responses, user input, file contents, env config) at the
system boundary before use. Fail fast with a clear message. Never trust external data.

## Additional Constraints

- **Toolchain**: Swift 6.2 / SPM. Platforms iOS 26+, macOS 26+. Strict concurrency on.
- **Localization**: default speech locale is `zh-Hans`. Code comments are in Chinese by
  convention; keep new comments consistent with surrounding code.
- **Protocol-driven DI**: core contracts are protocols; default implementations are `Default*`;
  test doubles are `Fake*` / `Mock*`. Depend on protocols, not concrete types.
- **File organization**: many small focused files over few large ones. Functions < 50 lines,
  files < 800 lines, nesting ≤ 4 levels.
- **LokiKit is external**: it lives at `~/Development/LokiKit` (referenced as `../../../LokiKit`),
  not inside this repository. Changes to LokiKit are out of scope for this repo's gates.

## Quality Gates

- **pre-commit / pre-push (local, bypassable)**: incremental layer build + that layer's tests +
  frontmatter anti-rot + "changed code must carry tests". Fast (< 60s target); no heavy verification.
- **CI required (server-side, unbypassable)**: full per-package tests, app-target build, and
  frontmatter validation, pinned to a fixed Xcode version. This is the only gate `--no-verify`
  cannot skip; heavy verification (`xcodebuild`, simulator) lives here, not in local hooks.
- Existing `local-review-skill` hooks (Codex review) are retained and run alongside these checks.

## Governance

This constitution supersedes ad-hoc practice. When a rule here changes, the corresponding
`red_lines` in each affected layer's `tech-context.md` frontmatter must be updated in the same
change — the projection must stay in sync. Amendments are deliberate: state the rule, the reason,
and the migration impact. Complexity that appears to require crossing a red line must be
redesigned, not excepted.

**Version**: 1.0.0 | **Ratified**: 2026-07-15 | **Last Amended**: 2026-07-15
