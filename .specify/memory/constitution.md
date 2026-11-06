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
VoxPocketApp → VoxPresentation → VoxApplication → VoxInfrastructure (VoxKitBridge)
                                      └──────────→ VoxKit SDK
VoxKit (VoxCore, VoxSpeech, VoxSpeechWhisperKit, VoxRefine, VoxLLM, VoxWorkflow,
       VoxWorkflowWhisperKit) → no local or external runtime layer
VoxInfrastructure → VoxDomain; VoxDomain → no dependencies
```

- `VoxKit` is a standalone SDK layer. Its modules (`VoxCore`, `VoxSpeech`,
  `VoxSpeechWhisperKit`, `VoxRefine`, `VoxLLM`, `VoxWorkflow`, and
  `VoxWorkflowWhisperKit`) have zero dependency on `VoxDomain`, `LokiKit`, or any
  App layer. `VoxInfrastructure` (`VoxKitBridge`), `VoxApplication`,
  `VoxPresentation`, and `VoxPocketApp` may depend downward on `VoxKit`.
- `VoxDomain` takes **no external dependencies** and imports no other local layer.
- No layer may import a layer above it. A lower layer reaching upward is a red line, not a refactor.
- This applies at two axes: **inter-layer** (package `depends_on`) and **intra-layer**
  (class stereotype `roles`, see the top-level tech-context `canonical_roles`). Lower role
  must not depend on higher role within a package either.

### III. Concurrency Safety (NON-NEGOTIABLE)
- Shared mutable state is guarded by `Mutex<State>` (from `Synchronization`), never by ad-hoc locks
  or unguarded `var`.
- View models and all UI code are `@MainActor`.
- `@unchecked Sendable` and `nonisolated(unsafe)` are permitted **only** for (a) App-side
  Combine bridging or (b) Apple system framework boundary callbacks (`AVFoundation` realtime
  audio tap and `Speech` recognition callbacks). Every such site carries an inline
  `// Sendable:` safety invariant comment. Third-party libraries, including WhisperKit, are not
  exempt; `VoxSpeechWhisperKit` uses an actor, `Mutex<State>`, or an `AsyncStream` continuation.
- No blocking calls (`Thread.sleep`, synchronous I/O, blocking waits) on the main thread — ever.
- Streaming uses `AsyncThrowingStream`; errors propagate, never silently dropped.

### IV. Privacy of Voice & Text (NON-NEGOTIABLE)
Recorded audio, live/final transcripts, and refined user text are sensitive user data.
- Never write transcript content, audio buffers, or refined user text into logs or telemetry payloads.
  Telemetry carries metrics only (durations, counts, source labels, session IDs) — never content.
- `VoxKit` is strictly bound by this principle: its entry points use compile-time typed
  `StaticString` messages and `VoxLogField` values (R3(a)); static checks prohibit `print`,
  `NSLog`, and `os_log` (R3(b)); dynamic Privacy Canary verification covers all entry points
  and presets (R3(c)).
- Never persist user content outside the app's own sandbox
  (`~/Library/Application Support/VoxPocket/`).

### V. Secrets & External-Vendor Hygiene (NON-NEGOTIABLE)
- No hardcoded secrets, API keys, or tokens in source. Only the App shell (`VoxPocketApp`)
  reads environment variables and the sandbox `config.private.json`; `VoxKit` never reads
  environment variables, `UserDefaults`, `Bundle`, `Keychain`, or uninjected file paths.
  Keys normally come from environment variables (`whisperkey`, `kimikey`/`AZURE_API_KEY`,
  `LOKI_TOKEN`, `CLAUDE_API_KEY`/`ANTHROPIC_API_KEY`) and are injected into the SDK.
  Validate required keys are present at startup; fail fast with a clear message.
- VoxKit receives credentials exclusively through `CredentialProvider` and its `Credential`
  value type, whose `description`, `debugDescription`, and `customMirror` are redacted; it
  receives storage paths only through `VoxStorageLocations`.
- Azure model credentials may alternatively come from the user-approved runtime file
  `Application Support/VoxPocket/config.private.json` inside the app sandbox (approved 2026-09-09).
  Require an owner-only regular file (0600), exclude it from backups, Git and application bundles,
  and never log its contents or decoder errors. Commit only a credential-free template.
  This enables ordinary app launches without a credential-injecting launcher; existing environment
  variables remain supported. Other credentials retain their existing environment-only contract.
- No Microsoft-specific identifiers in committed code: no Azure resource IDs, tenant IDs,
  Microsoft account references, Windows registry paths, OneDrive/SharePoint/Teams fields,
  or Microsoft copyright notices. Endpoints must come from config/env, not literals. Non-public
  integration configuration remains in gitignored `*.local.*` files with synthetic committed
  `*.example.*` templates.

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
- **VoxKit SDK boundary**: during phases 1–3 it is the staged package at `Packages/VoxKit`;
  from phase 4 it is a remote exact-version dependency. VoxKit's SDK redlines R1–R5 are
  verified by `Packages/VoxKit/scripts/redlines/check.sh --self-test`.
- **Non-public project configuration**: Azure hostnames, internal endpoints, and internal issue
  numbers never enter Git; use gitignored local files and commit only synthetic `.example` templates
  (`config.private.json`/`config.example.json` patterns).
- **LokiKit is external**: it is published by `LeePepe/shared-telemetry` and resolved by SwiftPM
  as a remote dependency pinned to exact `0.2.0`. Provider implementation changes are out of scope
  for this repo's gates. VoxPocket does not override `maxDiskBytes`: it accepts the provider's
  50 MiB default, whole-oldest-batch eviction, oversized-event rejection, and durable loss
  accounting. Before rollback to a reader without the capacity policy, producers stop and the
  capacity-aware reader completes pending eviction cleanup after storage is writable; loss-ledger
  state is retained, old and new writers never overlap, and already evicted events are irrecoverable.
- **Platforms**: macOS and iOS are both in development scope; CI builds and tests both. App
  delivery is TestFlight-only; iOS TestFlight releases need separate Owner authorization.

## Quality Gates

- **pre-commit / pre-push (local, bypassable)**: incremental layer build + that layer's tests +
  frontmatter anti-rot + "changed code must carry tests". pre-push runs `scripts/verify`, the same
  entry CI uses. Fast (< 60s target); no heavy verification.
- **CI required (server-side, unbypassable)**: full per-package tests, app-target build, and
  frontmatter validation, pinned to a fixed Xcode version. This is the only gate `--no-verify`
  cannot skip; heavy verification (`xcodebuild`, simulator) lives here, not in local hooks.
- Repository-owned `.githooks/` run the deterministic checks directly, including docs-map and
  freshness on commit. Internal AI Reviewer and PR Actions review responsibilities are unchanged.
- VoxKit SDK redlines R1–R5 (`Packages/VoxKit/scripts/redlines/check.sh --self-test`), VoxKit
  iOS Simulator tests, and App iOS Simulator unit tests are governance gates and are required
  once their corresponding targets are staged.

## Governance

This constitution supersedes ad-hoc practice. When a rule here changes, the corresponding
`red_lines` in each affected layer's `tech-context.md` frontmatter must be updated in the same
change — the projection must stay in sync. Amendments are deliberate: state the rule, the reason,
and the migration impact. Complexity that appears to require crossing a red line must be
redesigned, not excepted.

**Amendment (2026-09-20)**: Retire the duplicate local AI review dispatcher and its auto-fix
configuration. Preserve the existing deterministic checks through direct hook calls; this changes
hook ownership only, not layer red lines, CI requirements, or internal review responsibilities.

**Amendment (2026-09-24)**: Adopt the shared-ci repository contract: one `scripts/verify` entry for
hooks and CI, LokiKit pinned from shared-telemetry, iOS back in development scope (Owner decision Q6/Q12).
Layer red lines are unchanged.

**Amendment (2026-10-16, `loki02v1`)**: Adopt shared-telemetry exact `0.2.0` because its
synchronous legacy enqueue closes the enqueue/flush window and its bounded queue supplies the
reviewed retention policy. The Owner approved a one-time-only repository-contract deviation for the
atomic MY-1856 packet: the dependency pin, required non-trivial off-main adaptation, dependency
guards/current-truth projections, and this governance fact may ship in one candidate instead of
separate change kinds. This authorization applies only to that indivisible migration, creates no
general exception, changes no privacy/concurrency/layer red line, and does not authorize Blob
adoption, credentials, CI-gate changes, delivery changes, or shared-telemetry edits.

**Amendment (2026-11-05)**: Establish the VoxKit standalone SDK boundary and its R1–R5 governance redlines; stage its leaf context support before code promotion. This is a non-breaking governance amendment; migration moves the SDK from the staged package to an exact remote dependency in phase 4.

**Version**: 1.4.0 | **Ratified**: 2026-07-15 | **Last Amended**: 2026-11-05
