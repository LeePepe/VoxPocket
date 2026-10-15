# Implementation Plan: Privacy-safe Azure Blob product telemetry

**Feature**: `012-azure-blob-telemetry` | **Date**: 2026-10-15 | **Spec**: [`spec.md`](./spec.md)

**Planning branch**: `agent/planner-lead/38bb392a6f3b`

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**Input**: MY-1818 issue revision 1, Team Lead planning handoff, repository evidence, shared-telemetry integration contract, and the 2026-10-16 Lead decision `A-keep-0.2.0-offmain-accept-defaults`

## Summary

Adopt immutable shared-telemetry exact `0.2.0` and its Azure Blob adapter while preserving legacy Loki endpoint/routing/log-sink semantics. Because `0.2.0` persists legacy admissions synchronously, an ordered safety chain first adds the required app-test CI gate (PR01), then places every legacy Loki `track` and `flush` behind one app-lifetime serialized non-`@MainActor` coordinator while the old dependency is still selected (PR02), and only then moves every consumer/current truth to exact `0.2.0` (PR03). The later consented Blob path extends that same coordinator instead of creating a second executor. VoxPocket accepts the provider's default 50 MiB persisted-data cap, whole-oldest-batch eviction, oversized-event rejection, durable loss accounting, and capacity-aware rollback with no `maxDiskBytes` override. The Blob path remains separately routed, exposes only two typed product events, rejects non-allowlisted/private data before persistence, and constructs its dedicated retry store/service only for the interactive app after persisted “Send usage data” opt-in. Consent defaults off; disable stops admission/upload while retaining non-evicted pending files; first opt-in creates a persisted install UUID reused for the app installation's lifetime, with no v1 Reset surface. CLI, headless, and test hosts never construct Blob. Decision 2A exempts only the SDK-owned internally synchronized off-main heartbeat from the host seam. Decision 1A uses an Owner-created create-only stored-policy container service SAS. Real values enter an Owner-authorized macOS TestFlight archive only through a temporary untracked `0600` runner xcconfig whose path is passed with `-xcconfig`; required CI proves synthetic plist expansion and raw/escaped log absence. Governance/CI, runtime adaptation, dependency/pin, privacy, app, synthetic CI, and TestFlight work ship as independently working single-goal PRs.

## Technical Context

**Language/version**: Swift 6.2 packages/app; Python 3.11+ repository tests; Ruby/Fastlane; YAML/GitHub Actions; XcodeGen

**Primary dependencies**: shared-telemetry/LokiKit exact `0.2.0` (annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5`, peeled commit `903f4b9bc01cfcfeba3ce96e13519d841781b40a`); existing SwiftUI/AppKit app shell; shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`

**Storage**: existing Loki event store plus a dedicated Application Support Blob adapter catalog/event/sidecar/capacity store; both accept the provider-default 50 MiB persisted-data cap and loss ledger, remain separate from each other and from the independent Loki log-sink queue, and receive no consumer `maxDiskBytes` override

**Testing**: Swift Testing/XCTest package and app tests, including a required macOS app-unit-test CI invocation for the legacy off-main regression; repository Python/Ruby packaging fixtures; XcodeGen idempotency; unsigned synthetic macOS Release build with processed-plist inspection; policy/layer/full gates

**Target platform**: macOS app and manual macOS TestFlight release; iOS remains compile/test only and receives no TestFlight enablement

**Project type**: layered Swift desktop/mobile app with SwiftPM packages, XcodeGen app shell, and root release/CI support

**Performance goals**: no synchronous legacy Loki or Blob file I/O on `@MainActor`; one serialized app-lifetime coordinator for every underlying provider construction/`track`/`flush`; UI/lifecycle submission returns without waiting on file I/O; flush follows prior admission and one active flush exists at most; SDK heartbeat remains internally synchronized/off-main

**Constraints**: explicit persisted consent defaults off; no Blob construction in CLI/headless/test hosts; no audio/transcript/refined/prompt/error/credential telemetry; no generic strings; stored-policy service SAS with effective create-only permission; no user-delegation query fields; no value-bearing xcargs/environment/printable arguments; no live Azure CI; no committed real identifier; no implicit release dispatch; no queue-format migration or manual deletion; no `maxDiskBytes` override; capacity-aware rollback completes pending eviction cleanup before any older reader; disabled/failed/cancelled non-evicted events stay retryable; no test/gate weakening

**Scale/scope**: three dependency consumers, two current privacy boundaries, one default-off Settings consent surface, one app-lifetime Blob runtime and persisted install UUID, four closed user-action labels, one performance operation, two plist/build settings, and one Owner-gated release path

## Constitution Check — Before Research

| Principle / repository rule | Result | Plan response |
|---|---|---|
| I Immutability | PASS | Product events are immutable typed values; adapter files change only through the single owner. No existing user data is mutated. |
| II Layer direction | PASS | Infrastructure owns persisted preferences, Presentation owns the Settings view model/UI, Application hardens its telemetry boundary, app-shell composition owns Blob integration/host exclusion, and root support owns CI/release. No package imports the app. |
| III Concurrency safety | PASS | PR02 routes every legacy Loki `track`/`flush` through the serialized non-main lifecycle coordinator before PR03 selects `0.2.0`; later Blob construction/product `track`/lifecycle `flush` extends that same coordinator. Main-actor callers submit asynchronously; flushes follow earlier admissions and serialize/join. Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat work. |
| IV Privacy of voice/text | PASS | Exact allowlists and sentinel tests reject voice/text/prompt/error/credential content before accepted state; existing unsafe error fields are removed. |
| V Secrets/vendor hygiene | PASS | No real endpoint/SAS/resource identifier is committed or used in PR tests. Real values enter only through a runner-temp untracked `0600` xcconfig during an authorized TestFlight archive; only its path is printable, cleanup is unconditional, and raw/escaped sentinel absence is tested. |
| VI Boundary validation | PASS | Plist, adapter policy, labels, numeric bounds, exact dependency version/tag integrity, and processed Release output are validated fail-closed. |
| XcodeGen source of truth | PASS | `VoxPocket/project.yml` owns build settings/file membership; generated project changes are produced only by the pinned generator and checked for idempotency. |
| TestFlight-only production delivery | PASS | Local/PR verification is unsigned, synthetic, and non-networked. Production evidence remains post-merge and Owner-authorized. |
| Existing behavior / compatibility | PASS | Loki endpoint/Noop/routing/log-sink/release semantics remain. The Lead explicitly approves two bounded changes: provider work moves off caller/main thread through one serialized coordinator, and provider-default 50 MiB eviction/rollback semantics replace unbounded-retention assumptions. Arbitrary error strings are separately authorized for removal. |
| Important paths need Owner | PASS | Planning, CI governance, runtime adaptation, dependency/current truth, app-project, Fastlane, scripts, constitution, architecture, and context changes use their existing per-PR CODEOWNERS gates. No aggregate PR or evidence reuse is allowed. |

No constitutional exception is requested.

## Research Decisions

The evidence and alternatives are in [`research.md`](./research.md). Binding decisions:

1. **R-001 — Immutable repository-wide dependency**: move every consumer, guard, current authority, and current projection together to SwiftPM exact `0.2.0`; record the annotated tag object and peeled commit as integrity evidence only, with no branch or revision fallback.
2. **R-002 — Separate transports and stores**: Blob neither decorates nor mirrors Loki; it owns a dedicated store and must not migrate/delete Loki data.
3. **R-003 — Closed event vocabulary**: typed constructors expose only `product.user_action` and `product.performance`; heartbeat is SDK-owned.
4. **R-004 — One off-main serialized telemetry lifecycle**: PR02 introduces one app-lifetime non-`@MainActor` coordinator as the sole underlying caller for every legacy Loki `track` and `flush`; all existing injected callers retain only its `TelemetryService` facade. The coordinator preserves admission order and places flush after earlier admissions. PR06 extends this same seam for Blob bundle construction, product `track`, and lifecycle `flush`; Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat work.
5. **R-005 — Disabled before state**: missing/empty/unexpanded config creates no identity/store/network state; present-invalid config closes only Blob with a fixed diagnostic.
6. **R-006 — Release-only real configuration**: source plist uses build references; PR uses synthetic Release proof; TestFlight writes secrets only into a runner-temp untracked `0600` xcconfig, passes only its path via `-xcconfig`, cleans unconditionally, and proves raw/escaped sentinels absent from logs.
7. **R-007 — Privacy fix at owners**: Application/Infrastructure replace or remove arbitrary error strings and add boundary-specific sentinel regressions.
8. **R-008 — Compatibility first**: preserve Debug/local usability, endpoint/Noop/routing/log-sink semantics, manual macOS TestFlight, iOS compile/test-only behavior, signing/build/upload/tag logic, and every existing gate, except for the explicitly approved legacy off-main execution and provider-default bounded-retention changes.
9. **R-009 — Owner-gated single-goal PRs**: separate planning, required-CI governance, non-trivial runtime adaptation, dependency/current-truth, behavioral/privacy, app, synthetic-CI, and TestFlight-governance changes; do not bypass package/project/workflow/Fastlane/script/constitution/context ownership.
10. **R-010 — External production slice**: Owner provisioning/dispatch and Team Lead read-only blob evidence are separate from implementation completion.
11. **R-011 — Stored-policy service SAS**: Decision 1A uses key-authenticated policy permission `c` plus explicit expiry and an HTTPS-only container service SAS bound with `si`; stored-policy form omits `sp`, while any explicit `sp` must equal `c`.
12. **R-012 — Explicit consent, app-lifetime identity, and excluded hosts**: persist “Send usage data” in `UserDefaults` defaulting off; disable admission/upload without host/manual deletion, retain non-evicted pending files and the persisted UUID, create the random install UUID only on first opt-in, retain it inactive while off, and reuse the same UUID after later opt-in and eligible launches for the app installation's lifetime; expose no v1 install-ID Reset/rotation surface, require no shared-telemetry API change or private-storage parsing, and never construct Blob telemetry in CLI/headless/test hosts.
13. **R-013 — Accept provider capacity defaults and rollback contract**: pass no `maxDiskBytes` override to legacy Loki or Blob. Accept the pinned provider `ai/MIGRATION.md` default of 50 MiB for persisted source JSON/Blob sidecars, whole-oldest-batch eviction, oversized-event rejection, and durable dropped-event accounting. Before downgrade, stop producers and use the `0.2.0` capacity-aware reader to finish pending paired eviction cleanup after storage is writable; preserve the loss ledger and retained files, never overlap old/new writers, and treat already evicted events as unrecoverable.

## Design and Interfaces

### Product contract

[`contracts/product-telemetry-contract.md`](./contracts/product-telemetry-contract.md) is the single event/config/lifecycle contract. It defines four action labels, one operation, numeric bounds, prohibited value classes, whole-event rejection, fixed diagnostic categories, exact plist substitutions, and required evidence.

No package or app caller may expose arbitrary event names/property dictionaries for Blob. Trusted timestamp/provenance and bundle app/version/build values are added only inside the host/SDK boundary after policy validation.

### VoxInfrastructure privacy boundary

- Move `Packages/VoxInfrastructure/Package.swift` to the approved immutable dependency selection.
- Keep the existing telemetry name compatibility surface.
- Replace `String(describing: error)`/arbitrary `reason` emission in `WhisperKitTranscriber.swift` with a closed content-free failure category or omission.
- Add sentinel tests in `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/` proving no audio, transcript, stringified error, endpoint, or credential marker reaches telemetry.

### VoxApplication privacy boundary

- Move `Packages/VoxApplication/Package.swift` to the same immutable selection.
- Replace `error.localizedDescription` telemetry in `DefaultRefinementUseCase.swift` with a closed content-free outcome or omission while leaving UI/domain error propagation intact.
- Add tests in `Packages/VoxApplication/Tests/UseCasesTests/` proving no transcript, refined output, prompt, localized error, endpoint, or credential marker reaches telemetry.
- Preserve safe durations/counts and existing use-case dependency direction.

### VoxPresentation dependency boundary

- Move `Packages/VoxPresentation/Package.swift` to the same immutable selection.
- In PR07, add a focused telemetry Settings view model and extend `MacOSSettingsView` plus the existing cross-platform `MeRootView` privacy surface with the exact “Send usage data” toggle. The view model uses the Infrastructure preference contract and exposes no endpoint, SAS, UUID value, generic event API, app-shell dependency, or install-ID Reset/rotation action.
- Existing Settings pages, full-panel/quick-record behavior, and all other Presentation UI/view-model behavior remain preservation surfaces.

### VoxInfrastructure consent preferences

- In PR06, extend `PreferencesKey`/`UserDefaultsPreferencesStore` with the persisted consent and install-identity records plus focused isolated-suite coverage in `Packages/VoxInfrastructure/Tests/PreferencesTests/ProductTelemetryPreferencesTests.swift`. Consent absence reads as `false`; identity absence remains absence until first opt-in; a created identity persists across disable, remains inactive while off, and is reused after every later opt-in and eligible launch for the app installation's lifetime.
- The preference layer stores values only. It does not import Presentation or the app, construct telemetry, interpret Blob configuration, or perform admission/upload.

### VoxPocketApp shared telemetry lifecycle and Blob runtime

- In PR01 add only the required macOS App-target CI step that runs the existing `VoxPocketTests` target after XcodeGen, so the later regression will be executed rather than merely compiled.
- In PR02 add `TelemetryLifecycleCoordinator.swift` under `VoxPocket/VoxPocket/` and `TelemetryLifecycleCoordinatorTests.swift` under `VoxPocket/VoxPocketTests/` while the existing shared-telemetry version is still selected. `ServiceContainer` retains only the coordinator-backed `TelemetryService` facade and injects that facade into every existing App/Presentation/Application/Infrastructure caller. The coordinator lazily constructs the selected legacy provider on its dedicated serial non-main executor and is the only object allowed to invoke underlying legacy `track`/`flush`; it keeps admission FIFO and executes/joins flush only after prior admissions. A test begins on `@MainActor` and proves an underlying factory/spy observes construction plus both operations off-main and in order. Regenerate the tracked Xcode project from `project.yml` only if file membership changes.
- In PR06 extend that same `TelemetryLifecycleCoordinator.swift` for Blob lifecycle rather than adding a second executor; add `VoxPocketBlobTelemetry.swift`, `BlobTelemetryConfiguration.swift`, and `BlobTelemetryHostEligibility.swift` under `VoxPocket/VoxPocket/`; add `BlobTelemetryPolicyTests.swift`, `BlobTelemetryConfigurationTests.swift`, and `BlobTelemetryConsentTests.swift` under `VoxPocket/VoxPocketTests/`; register them only through `VoxPocket/project.yml`. PR07 adds `BlobTelemetryInstrumentationTests.swift` with the production adoption it verifies.
- The runtime reads exact plist keys and validates disabled/invalid/enabled state, but the interactive app constructs it only after persisted consent is on. Never-opted-in/off creates no service/store or identity and makes no identity-provider request. First opt-in creates one non-personal install UUID. Disabling after opt-in stops the live generation's admission/upload without host/manual deletion while retaining non-evicted pending files, capacity ledger state, and the persisted UUID without active-service identity request/use; every later explicit opt-in and eligible launch reuses that same UUID for the app installation's lifetime. V1 exposes no install-ID Reset/rotation action, makes no shared-telemetry API change for identity lifecycle, and does not parse adapter-private storage or catalog state.
- The same non-`@MainActor` coordinator becomes the sole host caller of the `AzureBlobTelemetryService` bundle initializer, omitting `maxDiskBytes` to accept the provider default, plus product `track` and lifecycle `flush`; enabled-service/store construction occurs through isolated asynchronous bootstrap. `ServiceContainer`, `AppDelegate`, and `MacOSAppScenes` schedule typed commands; they never construct an enabled store or call either provider synchronously. Tests admit only the SDK-owned internally synchronized heartbeat exemption.
- The composition boundary classifies the interactive app before service bootstrap. CLI, headless, and test hosts never create the Blob service even when synthetic configuration and preferences are present. The repository has no production CLI target, so CLI/headless behavior is proven by a negative host-kind fixture instead of inventing an executable.
- Record `app_launch` duration and the four accepted actions at successful semantic boundaries. Request flush after startup telemetry, recording/session completion, and macOS resign-active. Join the active flush; failure/cancellation causes no host/manual deletion, and non-evicted pending files remain retryable.
- Add exact source plist substitutions and synthetic Release settings through `Info.plist`, `Config.xcconfig`, and `project.yml`. Loki endpoint/Noop selection, event routing, and log sink remain separate; the only shared seam is the already-reviewed non-main lifecycle coordinator.

### Root dependency and release support

- In PR03, after PR02's adaptation has merged, update all active dependency consumers, guards, authorities, and exact-version projections together: the three manifests; `scripts/ci/fetch-external-deps.sh`; the dependency assertions in `scripts/tests/test_app_logging.py`; `AGENTS.md`; `.specify/memory/constitution.md`; `docs/architecture/tech-context.md`; `docs/architecture/packages-architecture.md`; `README.md`; `Packages/VoxInfrastructure/tech-context.md`; `Packages/VoxInfrastructure/OVERVIEW.md`; `Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/README.md`; `VoxPocket/tech-context.md`; `docker/telemetry/README.md`; and the stale dependency comment in `.github/workflows/testflight.yml`. This PR contains no runtime source/test adaptation or required-CI wiring. The constitution edit is a deliberate protected dependency-fact amendment naming rule, reason, migration impact, and version metadata; historical baseline statements in this feature's `spec.md`/`research.md` remain explicitly historical.
- Add a repository structural regression asserting production callers retain only the coordinator-backed facade, underlying legacy calls occur only inside the coordinator, and no consumer call spells `maxDiskBytes:`. Provider-owned queue-capacity correctness remains covered by the pinned `0.2.0` provider suite; VoxPocket verifies selection, omission of overrides, execution boundary, and rollback documentation rather than copying provider internals.
- Extend credential-free app/release tests and repository discovery as needed without removing existing assertions.
- Add a required unsigned synthetic Release build/check that inspects the processed app plist for exact fake expansion and no unresolved reference, signing, upload, or Azure contact.
- Extend `.github/workflows/testflight.yml` and `fastlane/Fastfile` only to create one untracked `0600` xcconfig in the runner temp directory, pass only its path through `-xcconfig`, and delete it via workflow `always` plus Fastlane `ensure`. Values never enter xcargs, command-line environment assignments, printable arguments, or logs. Preserve manual `workflow_dispatch`, checkout target, signing, numbering, upload, iOS disablement, and tag behavior.
- Update `docs/testflight-release.md` with placeholder-only operator semantics; the PR body, not committed documentation, carries the issue-accepted resource-specific Owner commands.

### Decision 1A Owner command contract

Agents do not run these commands, substitute real identifiers, inspect the generated token, or mutate Azure/GitHub secrets. The TestFlight-injection PR body must carry the same commands with the Owner's real values substituted at execution time:

```sh
az storage container policy create \
  --account-name "<storage-account>" \
  --container-name "<container>" \
  --name "<policy-name>" \
  --permissions c \
  --expiry "<YYYY-MM-DDTHH:MM:SSZ>" \
  --auth-mode key \
  --output none

az storage container generate-sas \
  --account-name "<storage-account>" \
  --name "<container>" \
  --policy-name "<policy-name>" \
  --https-only \
  --auth-mode key \
  --output tsv \
  | gh secret set TELEMETRY_BLOB_SAS --repo LeePepe/VoxPocket --app actions

gh secret set TELEMETRY_BLOB_ENDPOINT \
  --repo LeePepe/VoxPocket \
  --app actions
```

The second command deliberately omits `--permissions`, `--start`, and `--expiry`: the stored policy supplies authorization and expiry. Its emitted token normally has no `sp`; the effective permission is the policy's `c`, and the adapter still rejects any explicit `sp` other than `c`. The credential-free compatibility fixture is `sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D`; it proves the supported stored-policy shape without generating or storing a credential.

## Consumer migration and rollback notes

These notes intentionally accept, and do not override, the pinned shared-telemetry `v0.2.0` `ai/MIGRATION.md` contract:

- Legacy `LokiTelemetryService.track` now performs synchronous atomic persistence. VoxPocket removes that caller-visible main-thread cost by placing all legacy `track`/`flush` requests behind the single serialized non-main coordinator before exact `0.2.0` is published. Endpoint/token selection, safe event vocabulary, receiver, and flush triggers remain; caller-thread execution and immediate direct invocation do not.
- VoxPocket passes no `maxDiskBytes` override to either legacy Loki or Blob construction. The accepted provider default is 50 MiB of persisted source JSON plus Blob sidecars, excluding memory fallback, ledger metadata, and atomic-write transients. Whole oldest batches may be evicted, an oversized event may be rejected, and durable `droppedEventCount`/loss tombstones record loss. Already evicted events are unrecoverable.
- Rollback is capacity-aware: stop producers and active work, prevent old/new writer overlap, make the store writable, and let the `0.2.0` reader finish any pending paired eviction cleanup before a separately reviewed older reader opens the store. Preserve the loss ledger and retained files; otherwise an older reader can replay logically dropped files. Do not manually delete/convert files or claim provider migration notes as a product old→new→old drill.
- Release builds without `LOKI_ENDPOINT` still select `NoopTelemetryService`, so active legacy persistence/capacity impact is limited to Debug/local logging or an explicitly configured Release receiver. This rationale does not waive the executor or rollback contract.

## Implementation Slices

### PR00 — Land the reviewed planning package

Land only the exact AI-Reviewer-PASS planning artifacts and Spec Kit pointers before implementation. This PR contains no dependency/product/CI implementation and uses the normal CODEOWNERS path for `CLAUDE.md`.

### PR01 — Required app-unit-test CI gate

Add only the required macOS App-target `VoxPocketTests` invocation after the existing XcodeGen step. Current tests pass with signing disabled; no product code, test, dependency selector, constitution, architecture, or current-truth document changes.

### PR02 — Legacy off-main runtime adaptation

On the existing dependency version, introduce the shared app-lifetime telemetry coordinator, route every legacy Loki construction/`track`/`flush` operation through its serialized non-main executor, and prove from an `@MainActor`-originating test that the underlying spy is never called on the main thread. PR01's required CI runs this regression. No pin, guard, AGENTS, constitution, root architecture, or workflow change is included.

### PR03 — Exact 0.2.0 dependency/current-truth migration

After PR02 merges, validate annotated `v0.2.0` and its peeled commit, run the provider consumer fixture in version mode, then atomically move all three manifests, guards, active exact-version authorities/projections, protected constitution dependency-fact amendment, and stale dependency-only workflow comment to exact `0.2.0`. Accept the provider-default 50 MiB capacity/eviction/rollback contract with no `maxDiskBytes` override. PR02's runtime seam and regression remain unchanged and green; PR01's required CI executes them. This PR contains no non-trivial runtime adaptation.

### PR04 / PR05 — Independent privacy repairs

PR04 removes arbitrary stringified transcription-error telemetry in VoxInfrastructure; PR05 removes localized refinement-error telemetry in VoxApplication. Each contains its own red/green sentinel regression and preserves safe Loki metrics and runtime/UI error behavior. Each depends only on merged PR00 (or an explicitly approved base containing byte-identical reviewed planning artifacts), so both may proceed in parallel with the PR01→PR03 safety chain.

### PR06 — Dormant Blob deep module

After PR03, PR04, and PR05 merge, extend the existing shared coordinator with the typed Blob policy/configuration/store lifecycle, consent/identity preference state, host-eligibility policy, source plist/XcodeGen settings, and focused tests, but no production Blob call site. Missing/unexpanded source settings or default-off consent keep Blob unused and disabled. First-opt-in identity creation and app-lifetime reuse, live disable/re-enable with non-evicted pending-file retention, CLI/headless/test exclusion, default-capacity construction with no override, Decision 2A heartbeat boundary, Decision 1A query fixture, ordering, privacy, and disabled/invalid states are independently testable without credentials.

### PR07 — App adoption and instrumentation

Add the Presentation Settings consent-toggle surface, then activate the tested Blob portion of the shared coordinator through the interactive app composition in `ServiceContainer`, `AppDelegate`, and `MacOSAppScenes`. Emit only the four closed actions and launch performance event; add retry-safe lifecycle flushes. Default-off/disabled consent and CLI/headless/test hosts construct no Blob service. Opening Settings may retain its existing unrelated local-model access, but it must load consent independently and cannot make Blob construction a side effect. No install-ID Reset/rotation control, manifest, CI, Fastlane, or TestFlight secret wiring changes are included. The PR preserves PR02's legacy off-main coordinator and PR03's accepted default-capacity contract without adding another executor or override.

### PR08 — Synthetic Release CI

Add only the unsigned synthetic Release processed-plist helper, tests, and required CI wiring. Fake non-routable values are used; signing, upload, TestFlight, real secrets, and network senders are excluded.

### PR09 — TestFlight secure injection

Add only the authorized macOS TestFlight temp-`0600`-xcconfig path across workflow/Fastlane/tests/docs. Preserve the manual trigger, signing, numbering, upload, tag behavior, and iOS disablement. This PR alone carries the exact Decision 1A Owner commands and both secret-add commands.

### Production — Owner-controlled evidence

After PR01–PR09 merge, Owner policy/secret provisioning, and fresh Owner release authorization, the existing manual workflow produces one macOS TestFlight build. The tester separately enables “Send usage data” in Settings and performs one approved action; release authorization is not consent. Team Lead records only the build number, run/revision, blob name, and terminal category from read-only evidence.

## Acceptance Traceability

| Acceptance / requirement | Slice | Tasks | Evidence |
|---|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC6; FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-010, FR-011, FR-012, FR-015, FR-021 | PR06/PR07 | T008, T009 | typed contract; default-capacity initializer/heartbeat fixture; shared-coordinator ordering/join/retry; startup/action/flush adoption; preservation of the PR02/PR03 legacy seam |
| US1/AC5; FR-020; SC-006 | Production | T012 | explicit Owner authorization plus separate tester Settings opt-in; one approved action; exact merged/run revision; TestFlight build number; read-only blob name; no payload/credential evidence |
| US2/AC1; FR-005–FR-008, FR-015 | PR04–PR07 | T006–T009 | whole-event rejection plus Infrastructure/Application/app-shell privacy sentinels |
| US2/AC2; FR-008, FR-009; RB-001 | PR04/PR05 | T006, T007 | red/green localized/stringified-error tests and closed/omitted replacement fields |
| US2/AC3, US2/AC4; FR-010, FR-011 | PR06 | T008 | missing/empty/unexpanded zero-state and present-invalid fixed-diagnostic fixtures |
| US2/AC5; FR-014, FR-015, FR-016, FR-018, FR-019 | PR06/PR08/PR09 | T008, T010, T011 | SAS fixture; synthetic Release; temp-xcconfig/raw+escaped log absence; preserved gates |
| US3/AC1; FR-001 | PR03 | T002–T004, T013 | provider version-mode consumer check; exact `0.2.0`; matching manifests, guards, authorities, and projections; annotated-tag integrity evidence only |
| US3/AC6; FR-025; RB-004 | PR01/PR02 | T001, T005 | required app-test gate; off-main provider construction/`track`/`flush` spy; FIFO/flush barrier; zero raw-provider bypass |
| US3/AC7; FR-026; RB-005 | PR03/PR06/PR07 | T002–T004, T008, T009, T013 | legacy and Blob default-capacity construction/adoption; zero `maxDiskBytes` override; accepted eviction, loss-accounting, and rollback notes |
| SC-008 | PR01–PR03/PR06/PR07 | T001, T005, T008, T009, T013 | required main-actor-originating off-main/FIFO regression plus structural zero-bypass and zero-override inspection across legacy and Blob paths |
| US3/AC2; FR-002, FR-003, FR-008, FR-009, FR-025 | PR02–PR05/PR07 | T002–T007, T009, T013 | preserved endpoint/Noop/routing/log-sink semantics; shared legacy executor; privacy-only removals; no Blob fan-out |
| US3/AC3; FR-013, FR-015, FR-016 | PR06/PR08 | T008, T010 | XcodeGen/plist contract and processed synthetic Release app |
| FR-017 | PR06–PR09 | T008–T011 | source settings, adoption, processed Release proof, and TestFlight path stay aligned |
| US3/AC4; FR-014, FR-015, FR-016, FR-018 | PR09 | T011 | path-only `-xcconfig`; mode/cleanup; raw+escaped absence; unchanged release invariants |
| US3/AC5; FR-018, FR-019; SC-005 | PR00–PR09 | T000–T011, T013 | per-PR one-goal/exact-head evidence and applicable Owner gates; exact commands only in PR09 |
| US1/AC7, US1/AC8, US2/AC6; FR-022–FR-024; SC-007 | PR06/PR07 | T008, T009 | isolated `UserDefaults` consent/identity fixtures; macOS/cross-platform Settings consent-toggle tests; first-opt-in random UUID creation; disable→off no-host-deletion/non-evicted-file plus UUID retention→later-opt-in and eligible-launch reuse of the same app-lifetime UUID; no v1 Reset/rotation surface; excluded-host zero-construction fixtures |
| SC-001 | PR04–PR07 | T006–T009 | all supplied prohibited sentinels rejected before persistence/transport |
| SC-002 | PR06 | T008 | zero identity-provider/store/enqueue/network calls for disabled Debug/Release fixtures |
| SC-003 | PR08/PR09 | T010, T011 | expanded synthetic plist plus zero raw/escaped sentinels or value-bearing arguments/logs |
| SC-004 | PR01–PR09 | T001–T011, T013 | each PR's focused verification, `scripts/verify`, exact-tree review, and no weakened test |

Every stable acceptance criterion and functional requirement maps to an owned task and evidence surface. RB-001 is the approved arbitrary-error removal; RB-002 preserves separation by forbidding legacy Loki fan-out; RB-003 preserves host-controlled queue files and every other transport, metric, guard, test, signing/upload step, and platform restriction; RB-004/RB-005 are the explicit Lead-approved legacy execution and bounded-retention changes. Production-only acceptance remains explicitly external rather than being claimed by repository tests.

## Verification Strategy

[`quickstart.md`](./quickstart.md) is the executable verification contract. Required implementation evidence:

1. After PR00, PR01 adds only required App-target CI that regenerates the Xcode project and executes `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -destination 'platform=macOS' -only-testing:VoxPocketTests test` with signing disabled; the existing suite passes before any runtime or pin change;
2. PR02, still on the old provider version, uses a main-actor-originating spy to prove legacy provider construction, `track A`, `track B`, and barrier `flush` occur FIFO with maximum underlying concurrency one and `Thread.isMainThread == false`; structural evidence proves no raw-provider bypass, and PR01's required CI executes the regression;
3. PR03 validates annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peeling to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, runs `external_consumer.py --version 0.2.0`, updates the full current-truth path list atomically, proves old selectors absent and no consumer `maxDiskBytes` override, and reruns PR02's regression without changing its runtime source/tests;
4. Independently after PR00 and in parallel with the PR01→PR03 chain, PR04 and PR05 each demonstrate their privacy test red against the unsafe baseline, then green without assertion weakening, and pass their own package layer plus `scripts/verify`;
5. Only after PR03, PR04, and PR05 merge, PR06 proves the representative stored-policy query accepted and `sp=cw`/user-delegation/unknown-name forms rejected; it extends the reviewed coordinator and tests provider-default Blob construction with no `maxDiskBytes` argument, SDK heartbeat exemption, coordinator-only host construction/`track`/`flush`, privacy allowlists, disabled/invalid config, default-off consent, first-opt-in UUID creation, disable→off no-host-deletion/non-evicted-file plus UUID retention, later-opt-in and eligible-launch reuse of the same app-lifetime UUID, no v1 install-ID Reset/rotation surface, excluded-host policy, ordering, joined flush, and non-evicted retryability;
6. PR07 proves macOS/cross-platform Settings UI wiring, excluded-host composition, interactive-app consent adoption, app-shell action/lifecycle instrumentation, and preservation of PR02's off-main legacy coordinator plus PR03's default-capacity behavior while unconfigured or non-consented Blob remains disabled;
7. PR08 generates from `VoxPocket/project.yml`, proves zero generated drift, and inspects an unsigned synthetic Release app's processed plist;
8. PR09 proves the xcconfig is runner-temp/untracked/`0600`, only its path reaches `-xcconfig`, cleanup runs on every terminal path, both raw and escaped sentinels are absent from captured Release logs, and existing manual release invariants remain;
9. every implementation PR passes its focused commands, `scripts/verify`, `git diff --check`, and required CI; PRs forcing full selection also run `scripts/verify --all` locally when practical and rely on the required full CI lanes at the exact head;
10. every PR freezes its own candidate for independent content review before publication, publishes only that tree, and proves equality of local SHA, remote branch OID, and PR `headRefOid`; evidence is never reused across PRs;
11. stacked branches declare their parent; after a prerequisite squash-merges, the child is retargeted/rebased onto `origin/main`, then fully reverified and rereviewed because its SHA changed;
12. production proof occurs only after PR01–PR09 merge, Owner provisioning, a new explicit Owner authorization, and a separate tester opt-in through “Send usage data”; authorization never substitutes for consent.

No local or PR verification performs a signed archive, TestFlight upload, GitHub secret write, Azure request, or blob listing.

## Project Structure

```text
specs/012-azure-blob-telemetry/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── product-telemetry-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md

AGENTS.md
README.md
.specify/memory/constitution.md
docs/architecture/
├── tech-context.md
└── packages-architecture.md

Packages/VoxInfrastructure/
├── Package.swift
├── tech-context.md
├── OVERVIEW.md
├── Sources/Preferences/PreferencesStore.swift
├── Sources/TranscriptionKit/
│   ├── VoxPocketTelemetryEventName.swift
│   └── WhisperKitTranscriber.swift
├── Tests/PreferencesTests/ProductTelemetryPreferencesTests.swift
└── Tests/TranscriptionKitTests/

Packages/VoxApplication/
├── Package.swift
├── Sources/UseCases/DefaultRefinementUseCase.swift
└── Tests/UseCasesTests/

Packages/VoxPresentation/
├── Package.swift
├── Sources/UIShared/ViewModels/ProductTelemetrySettingsViewModel.swift
├── Sources/UIShared/Views/MacOSSettingsView.swift
├── Sources/UIShared/Views/MeRootView.swift
├── Tests/UISharedTests/MacOSSettingsViewTests.swift
├── Tests/UISharedTests/ProductTelemetrySettingsViewModelTests.swift
└── Tests/UISharedTests/ProductTelemetrySettingsViewTests.swift

VoxPocket/
├── Config.xcconfig
├── project.yml
├── VoxPocket/
│   ├── Info.plist
│   ├── ServiceContainer.swift
│   ├── AppDelegate.swift
│   ├── MacOSAppScenes.swift
│   ├── VoxPocketBlobTelemetry.swift
│   ├── BlobTelemetryConfiguration.swift
│   ├── BlobTelemetryHostEligibility.swift
│   └── TelemetryLifecycleCoordinator.swift
└── VoxPocketTests/
    ├── TelemetryLifecycleCoordinatorTests.swift
    ├── BlobTelemetryPolicyTests.swift
    ├── BlobTelemetryConfigurationTests.swift
    ├── BlobTelemetryConsentTests.swift
    ├── BlobTelemetryConsentCompositionTests.swift
    └── BlobTelemetryInstrumentationTests.swift

scripts/ci/fetch-external-deps.sh
scripts/ci/run_repository_tests.py
scripts/tests/test_app_logging.py
scripts/tests/test_blob_telemetry_release.py
scripts/tests/test_testflight_freshness.py
scripts/tests/test_testflight_packaging.rb
.github/workflows/ci.yml
.github/workflows/testflight.yml
fastlane/Fastfile
docs/testflight-release.md
docker/telemetry/README.md
```

**Structure decision**: PR01 adds only required app-test CI; PR02 adds the minimal VoxPocketApp coordinator seam on the old provider version; PR03 then updates all consumers/current exact-version truth and accepted migration notes without runtime feature code. PR04/PR05 own privacy behavior separately and may proceed after PR00 in parallel with that ordered chain. PR06 waits for PR03–PR05 and extends the existing coordinator into the dormant consent-capable Blob deep module plus Infrastructure preference state. PR07 is one vertical adoption goal across Presentation Settings and VoxPocketApp composition; it reuses the seam and does not add another executor. Root support splits synthetic CI (PR08) from TestFlight secret governance (PR09). Generated Xcode project files are outputs, never hand-edited sources.

## Constitution Check — After Design

PASS with no constitutional exception. PR01, PR02, and PR03 deliberately separate the required CI gate, non-trivial runtime adaptation, and immutable dependency/current-truth migration. The legacy provider is constructed and invoked only on one dedicated serial non-main executor before `0.2.0` is selected, and a main-actor-originating spy proves the boundary in required CI. The design preserves package direction, makes every underlying legacy/Blob construction/`track`/`flush` structurally non-main, defaults consent off at the preference/app-composition boundary, excludes non-interactive hosts before Blob construction, narrowly records Decision 2A for SDK-owned heartbeat, rejects private/free-form data before accepted state, uses synthetic credential-free CI, keeps XcodeGen authoritative, isolates Blob files from Loki, and separates Owner-controlled release evidence from implementation authority. The authorized execution-timing, default-capacity/eviction/rollback, and arbitrary-error changes are explicit and test/document-covered; every other legacy/release behavior remains a preservation surface.

## Dependencies and External Gates

- Repository base: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`.
- Repo contract: shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`.
- Provider dependency: shared-telemetry exact `0.2.0`; annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peels to reviewed commit `903f4b9bc01cfcfeba3ce96e13519d841781b40a`. Those OIDs are integrity evidence, not revision selectors.
- Planning gate: AI Reviewer exact-revision PASS before Team Lead implementation dispatch.
- Per-PR candidate gate: AI Reviewer exact frozen-tree PASS plus explicit publication permission before each commit/push/PR; a changed or rebased SHA is reviewed again.
- Important-path gate: applicable Owner approval and required checks on each exact non-Draft PR head.
- Production gate: PR01–PR09 merged; Owner-created create-only stored policy/container service SAS; both GitHub secrets; a new explicit Owner authorization before manual TestFlight dispatch; then a separate tester Settings opt-in before the approved action used for evidence.

## Risks and Escalation Conditions

| Risk | Mitigation / escalation |
|---|---|
| `v0.2.0` is missing, moved, not annotated, or peels to a commit other than `903f4b9bc01cfcfeba3ce96e13519d841781b40a` | Block PR03 and escalate the exact tag evidence. Do not fall back to a branch or revision selector; ordinary later movement of provider `main` is irrelevant. |
| SDK API differs from reviewed docs | Stop and return exact compiler/provider-contract evidence; do not invent an adapter wrapper or widen shared-telemetry scope. |
| Stored-policy SAS query differs | Compare the synthetic query-name fixture against the pinned validator. Reject user-delegation keys or `sp=cw`; do not broaden the provider or generate a real token. |
| Synchronous provider I/O leaks onto `@MainActor` | Dedicated serial non-main executor plus a main-actor-originating spy covering provider construction, `track A`, `track B`, and barrier `flush`; structural assertions reject raw-provider bypass. A generic actor-isolation claim without `Thread.isMainThread == false` evidence is insufficient. SDK heartbeat remains only the Decision 2A exemption. |
| Consent or host exclusion is bypassed | Central composition classification plus isolated preference/UI/app fixtures. Any eager identity/service creation, off-state admission/upload, implicit resume, host/manual pending-file deletion, or CLI/headless/test construction blocks review. Provider-owned eviction under the accepted capacity policy is not a bypass. |
| Privacy policy requires arbitrary strings | Reject the event or add a new Owner-approved closed label. Never sanitize/redact after persistence. |
| Store lease/capacity/rollback behavior is incompatible | Keep the 50 MiB provider default and loss ledger; stop producers, finish pending eviction cleanup with the capacity-aware `0.2.0` reader after storage is writable, and never overlap old/new writers. Already evicted events are unrecoverable. Return exact adapter evidence rather than adding an override or manually reusing/deleting persisted state. |
| XcodeGen produces unexpected drift | Stop with generator version and diff. Do not hand-edit the generated project or absorb unrelated output. |
| Synthetic Release proof needs signing/network | Treat as a design failure and return to the app/root-support owner; do not introduce secrets or live access. |
| Secret or sentinel value appears in logs/arguments/tests/diff | Stop publication, rotate if real, remove the exposure through the owning release seam, and rerun raw-plus-escaped absence evidence. Masking alone is not acceptance. |
| Important approval/check is missing | Keep the PR unmerged in Owner review; never bypass CODEOWNERS/ruleset protection. |
| Owner has not provisioned/authorized production, or tester consent is absent | Repository delivery may complete, but T012 remains blocked; no workflow is dispatched without Owner authority and no telemetry action/blob evidence is attempted without separate tester opt-in. |

## Complexity Tracking

No constitutional violation is requested. The PR03 constitution amendment changes the selected immutable dependency fact, not a red line, and records rule/reason/migration impact with matching projections; it is separate from PR02's runtime feature code and PR01's CI governance. The shared coordinator/executor is required by the provider's synchronous construction/persistence boundary and deepens the app interface: legacy callers retain the existing `TelemetryService` surface while all provider work is serialized off-main; later Blob callers submit two typed event variants and lifecycle commands without knowing configuration, identity, store, capacity policy, transport, or SDK heartbeat details.
