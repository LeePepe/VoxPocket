# Research: Privacy-safe Azure Blob product telemetry

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**Accepted intent**: MY-1818 issue revision 1

**Date**: 2026-10-15

## Dependency evidence

- VoxInfrastructure, VoxApplication, and VoxPresentation all pin shared-telemetry `v0.1.0` at `5f4b4d97d7ad05adb849e0d8937c8745d9b6d15f`; the same revision is guarded by `scripts/ci/fetch-external-deps.sh` and `scripts/tests/test_app_logging.py`.
- The reviewed shared-telemetry `main` revision is `0ffdbc82a5fbd76f54e49127b0d30a4fb8666e95`. It contains the public Swift Azure Blob adapter and its integration, usage, migration, and compatibility contracts.
- The remote does not publish `v0.2.0` at planning time. Implementation must therefore use the full reviewed revision unless the immutable tag exists before publication, in which case every consumer moves together to exact `0.2.0` and records the resolved SHA.
- The adapter performs synchronous event admission/local persistence, owns a retryable file store, validates create-only SAS intent, emits an SDK-owned content-free heartbeat, and leaves upload explicit through `flush()`.

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

All three Swift consumer manifests and both dependency guards use one selection. Until `v0.2.0` exists, the selection is the reviewed full SHA `0ffdbc82a5fbd76f54e49127b0d30a4fb8666e95`; a later tag switch is allowed only before implementation publication and only when its resolved revision is recorded and all consumers move atomically.

**Rejected**: a branch pin, short SHA, mixed manifest revisions, or assuming the documented release tag exists.

### R-002 — Keep Loki and Blob as separate products and stores

The existing Loki event service and `VoxPocketLogging` remain unchanged in ownership and routing. A new Blob-only app runtime accepts only the two product event types and uses a dedicated Application Support directory. No Loki event is mirrored into Blob, and no Loki queue/log file is opened, migrated, or deleted.

**Rejected**: decorating the existing telemetry service with implicit dual-write, sharing a queue, or treating Loki logs as product analytics.

### R-003 — Admit a closed product vocabulary

The product contract contains exactly `product.user_action` and `product.performance`. Product callers use typed constructors; the policy rejects unknown names, keys, labels, free text, non-finite values, and out-of-range durations as a whole before accepted state. `telemetry.heartbeat` remains SDK-owned operational diagnostics.

**Rejected**: a generic `[String: Any]` event helper, arbitrary error descriptions, session/user identifiers, model names, transcripts, or URLs.

### R-004 — Serialize synchronous adapter work off `@MainActor`

One non-`@MainActor` actor owns the Blob service for the app lifetime. UI and app-lifecycle code submits typed commands asynchronously. The actor serializes admission and local persistence, drains prior admission before flush, and joins an in-flight flush rather than starting a competing request. Resign-active schedules a best-effort non-blocking flush; failed or cancelled pending files remain retryable.

**Rejected**: direct `track` calls from `ServiceContainer`, view models, SwiftUI scenes, or `AppDelegate`, and unretained competing flush tasks.

### R-005 — Disable before constructing state

The host reads `LokiKitBlobEndpoint` and `LokiKitBlobSAS`. Missing, empty, or unexpanded values select the SDK-disabled path before identity, store, or network construction. Present-invalid values fail only Blob closed and produce one fixed diagnostic with no supplied value. The install identity is a non-personal UUID requested only for a first valid store or explicit reset.

**Rejected**: environment fallback, partial enablement, implicit development receiver, or logging the rejected value.

### R-006 — Inject real values only into the authorized TestFlight archive

Source plist values are build-setting references. Pull requests and local verification use no real values. The manual TestFlight workflow maps GitHub secrets to the existing Fastlane lane; the lane passes opaque build settings without printing the values. A required synthetic Release check uses unmistakably fake values and inspects the processed plist without signing, upload, or Azure access.

**Rejected**: repository secrets in plist/xcconfig, live Azure CI, endpoint probing, automatic releases, or exposing secrets through command/result logging.

### R-007 — Harden existing telemetry at its owning boundaries

VoxApplication and VoxInfrastructure replace arbitrary error strings with reviewed closed categories or omit the field. Sentinel tests prove that localized/stringified errors and voice/text markers never cross either boundary. UI error presentation remains unchanged.

**Rejected**: sanitizing after persistence, substring redaction, or disabling the existing failure event entirely without preserving its safe metrics/category.

### R-008 — Preserve release and platform behavior

Debug/local builds and credential-free Release builds run with Blob disabled. The existing macOS manual TestFlight trigger, signing, build numbering, upload, and release-tag behavior remain. No iOS TestFlight path, background entitlement, or automatic trigger is added.

### R-009 — Treat CODEOWNERS changes as Owner-gated

Package manifests, `project.yml`, `.github/**`, `fastlane/**`, `scripts/ci/**`, AGENTS, and layer context paths remain under their existing Owner/review contracts. The implementation PR is non-Draft and important, contains the accepted Owner commands, and cannot merge without Owner approval and required checks.

### R-010 — Separate repository delivery from production proof

Credential-free tests and reviewed PR delivery prove the implementation. Creating the SAS, adding two GitHub secrets, dispatching TestFlight, and listing the resulting blob remain post-merge Owner/Team Lead work. Agents neither provision nor dispatch those actions implicitly.

## Compatibility and removed behavior

- Shared-telemetry adoption is additive at the module/product level; all consumers move together to avoid mixed resolution.
- Existing Loki endpoint/token selection, Noop fallback, event routing, log-sink filtering, stores, and safe metrics remain.
- The only intentional runtime-payload removal is arbitrary localized/stringified error text. Closed failure categories may replace it; UI error display is unaffected.
- Rollback stops the Blob owner and retains Blob catalog/queue/sidecar/capacity-ledger files. The older adapter must not open them. Already transmitted events cannot be retracted.
- No test, assertion, policy check, release guard, signing step, upload step, or platform restriction may be removed or weakened.

## Open external gates

1. `v0.2.0` tag availability must be rechecked immediately before implementation publication.
2. Package-manifest, XcodeGen, workflow, Fastlane, and CI edits require existing CODEOWNERS/Owner review.
3. Real endpoint/SAS provisioning and the TestFlight dispatch require explicit Owner action after merge.
4. Final production evidence is limited to run/revision, build number, and blob name; payload and credentials are excluded.
