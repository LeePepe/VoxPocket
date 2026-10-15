# Research: Privacy-safe Azure Blob product telemetry

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**Accepted intent**: MY-1818 issue revision 1

**Date**: 2026-10-15

## Dependency evidence

- VoxInfrastructure, VoxApplication, and VoxPresentation all pin shared-telemetry `v0.1.0` at `5f4b4d97d7ad05adb849e0d8937c8745d9b6d15f`; the same revision is guarded by `scripts/ci/fetch-external-deps.sh` and `scripts/tests/test_app_logging.py`.
- The original planning snapshot predated `v0.2.0` publication. Current remote evidence supersedes that dependency-selection assumption: annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peels to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, which was also provider `main` when verified.
- PR01 must use SwiftPM `exact: "0.2.0"` everywhere. The tag object and peeled commit are integrity evidence only; neither a branch nor a revision selector is an allowed fallback.
- The adapter performs synchronous event admission/local persistence, owns a retryable file store, validates create-only SAS intent, emits an SDK-owned content-free heartbeat, and leaves upload explicit through `flush()`.
- At released provider commit `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, the transport accepts only `sv`, `sr`, `si`, `sp`, `st`, `se`, `spr`, `sip`, and `sig`; requires `sr=c`; and rejects an explicit `sp` other than `c`. The prior `--permissions cw --auth-mode login --as-user` command emits both `sp=cw` and unsupported user-delegation keys, so it cannot initialize this adapter.
- The exact bundle initializer immediately records/schedules the SDK heartbeat under the SDK's own synchronization, with later ticks originating off-main. That internal work cannot traverse a host actor and is the narrow Decision 2A exemption.

## Repository evidence

- `ServiceContainer.makeTelemetryService()` owns the existing Loki event service. Debug selects localhost; Release without `LOKI_ENDPOINT` selects `NoopTelemetryService`.
- `VoxPocketLogging` independently owns the local-log-to-Loki sink and persisted log queue. It is not the product-event integration seam.
- App lifecycle and user-action seams already exist in `AppDelegate.swift`, `MacOSAppScenes.swift`, and `ServiceContainer.swift`. They run on `@MainActor`; the shared adapter's synchronous admission must not run there.
- `DefaultRefinementUseCase.swift` forwards `error.localizedDescription`; `WhisperKitTranscriber.swift` forwards a stringified error as `reason`. Existing tests do not mechanically prove those payloads content-free.
- The app has no Blob plist keys, Blob-only store, Blob identity, Blob lifecycle owner, or Release expansion proof.
- The TestFlight workflow is manual `workflow_dispatch`, checks out `main`, publishes macOS only, and delegates archive/upload to Fastlane. iOS TestFlight remains disabled.
- Current required app CI builds Debug. A synthetic unsigned Release lane is required to inspect the processed plist without credentials or network access.

## Decisions

### R-001 — Use an immutable, repository-wide shared-telemetry selection

All three Swift consumer manifests, both dependency guards, and every current authority/projection use SwiftPM exact `0.2.0`. PR01 validates the annotated tag object and peeled commit, records them as integrity evidence, and moves the entire selection atomically; tag-integrity failure blocks and escalates instead of selecting a revision.

**Rejected**: a branch or revision pin, revision fallback, semver range, short SHA, mixed selections, or an unverified/moved tag.

### R-002 — Keep Loki and Blob as separate products and stores

The existing Loki event service and `VoxPocketLogging` remain unchanged in ownership and routing. A new Blob-only app runtime accepts only the two product event types and uses a dedicated Application Support directory. No Loki event is mirrored into Blob, and no Loki queue/log file is opened, migrated, or deleted.

**Rejected**: decorating the existing telemetry service with implicit dual-write, sharing a queue, or treating Loki logs as product analytics.

### R-003 — Admit a closed product vocabulary

The product contract contains exactly `product.user_action` and `product.performance`. Product callers use typed constructors; the policy rejects unknown names, keys, labels, free text, non-finite values, and out-of-range durations as a whole before accepted state. `telemetry.heartbeat` remains SDK-owned operational diagnostics.

**Rejected**: a generic `[String: Any]` event helper, arbitrary error descriptions, session/user identifiers, model names, transcripts, or URLs.

### R-004 — Serialize synchronous adapter work off `@MainActor`

One non-`@MainActor` actor owns the Blob service for the app lifetime and is the sole host entry for the exact bundle initializer, product `track`, and lifecycle `flush`. UI and app-lifecycle code submits typed commands asynchronously. The actor serializes host admission/local persistence, drains prior admission before flush, and joins an in-flight flush rather than starting a competing request. Resign-active schedules a best-effort non-blocking flush; failed or cancelled pending files remain retryable. Decision 2A narrowly exempts only SDK-owned, internally synchronized, content-free startup/daily heartbeat work; it creates no host/product bypass.

**Rejected**: direct `track` calls from `ServiceContainer`, view models, SwiftUI scenes, or `AppDelegate`; product-emitted heartbeat; a second store owner; forcing SDK heartbeat through a host scheduler; and unretained competing flush tasks.

### R-005 — Disable before constructing state

The host reads `LokiKitBlobEndpoint` and `LokiKitBlobSAS`. Missing, empty, or unexpanded values select the SDK-disabled path before identity, store, or network construction. Present-invalid values fail only Blob closed and produce one fixed diagnostic with no supplied value. The install identity is a non-personal UUID requested only for a first valid store or explicit reset.

**Rejected**: environment fallback, partial enablement, implicit development receiver, or logging the rejected value.

### R-006 — Inject real values only into the authorized TestFlight archive

Source plist values are build-setting references. Pull requests and local verification use no real values. Under the binding Owner decision, the manual TestFlight workflow writes both GitHub secret values into one untracked runner-temp xcconfig, enforces mode `0600`, passes only its path through `-xcconfig`, and deletes it through `always`/`ensure` on success, failure, or cancellation. Values never enter xcargs, command-line environment assignments, printable arguments, or logs. A required synthetic Release check inspects the processed plist without signing/upload/Azure access; packaging fixtures prove both raw and escaped sentinels absent from Release logs.

**Rejected**: tracked or workspace-persistent credential files; value-bearing environment/xcargs/arguments; reliance on masking alone; repository secrets in plist/xcconfig; live Azure CI; endpoint probing; automatic releases; or exposing secrets through command/result logging.

### R-007 — Harden existing telemetry at its owning boundaries

VoxApplication and VoxInfrastructure replace arbitrary error strings with reviewed closed categories or omit the field. Sentinel tests prove that localized/stringified errors and voice/text markers never cross either boundary. UI error presentation remains unchanged.

**Rejected**: sanitizing after persistence, substring redaction, or disabling the existing failure event entirely without preserving its safe metrics/category.

### R-008 — Preserve release and platform behavior

Debug/local builds and credential-free Release builds run with Blob disabled. The existing macOS manual TestFlight trigger, signing, build numbering, upload, and release-tag behavior remain. No iOS TestFlight path, background entitlement, or automatic trigger is added.

### R-009 — Treat CODEOWNERS changes as Owner-gated

Package manifests, `project.yml`, `.github/**`, `fastlane/**`, `scripts/ci/**`, AGENTS, the constitution, architecture, and layer context paths remain under their existing Owner/review contracts. Dependency, product/privacy adaptation, synthetic CI, and TestFlight governance are separate single-goal PRs. PR01 dependency selection, PR02 Infrastructure privacy, and PR03 Application privacy have disjoint paths/outputs, share PR00 as their sole prerequisite, and may run concurrently; PR04 waits for all three. Every PR independently leaves `main` working, runs `scripts/verify`, receives exact-tree review/publication permission, and binds evidence to its own head; applicable important PRs cannot merge without Owner approval and required checks.

### R-010 — Separate repository delivery from production proof

Credential-free tests and reviewed PR delivery prove the implementation. Creating the SAS, adding two GitHub secrets, dispatching TestFlight, and listing the resulting blob remain post-merge Owner/Team Lead work. Agents neither provision nor dispatch those actions implicitly.

### R-011 — Use a create-only stored-policy container service SAS

Decision 1A supersedes the issue's incompatible user-delegation example. The Owner uses key-based authentication to create a stored access policy with permission `c` and explicit UTC expiry, then generates an HTTPS-only container service SAS with `--policy-name`. The token uses only provider-supported names and contains `sr=c`, non-empty `si`/`sig`, optional `sv`, and `spr=https`; permission is carried by the policy, so stored-policy form normally omits `sp`, while any explicit `sp` must equal `c`. A synthetic representative-query fixture proves this shape and rejects `sp=cw` plus user-delegation fields.

**Rejected**: `--auth-mode login --as-user`; direct `cw`; adding provider support for user-delegation fields; agents generating/inspecting/storing the real token; or placing real resource identifiers in committed artifacts.

## Compatibility and removed behavior

- Shared-telemetry adoption is additive at the module/product level; all consumers move together to avoid mixed resolution.
- Existing Loki endpoint/token selection, Noop fallback, event routing, log-sink filtering, stores, and safe metrics remain.
- The only intentional runtime-payload removal is arbitrary localized/stringified error text. Closed failure categories may replace it; UI error display is unaffected.
- Rollback stops the Blob owner and retains Blob catalog/queue/sidecar/capacity-ledger files. The older adapter must not open them. Already transmitted events cannot be retracted.
- No test, assertion, policy check, release guard, signing step, upload step, or platform restriction may be removed or weakened.

## Open external gates

1. Immediately before PR01 publication, annotated `v0.2.0` must still peel to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`; a missing/moved/mismatched tag blocks and escalates without a revision fallback.
2. Package-manifest, XcodeGen, workflow, Fastlane, and CI edits require existing CODEOWNERS/Owner review.
3. Real endpoint/SAS provisioning and the TestFlight dispatch require explicit Owner action after merge.
4. Final production evidence is limited to run/revision, build number, and blob name; payload and credentials are excluded.
