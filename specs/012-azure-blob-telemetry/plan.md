# Implementation Plan: Privacy-safe Azure Blob product telemetry

**Feature**: `012-azure-blob-telemetry` | **Date**: 2026-10-15 | **Spec**: [`spec.md`](./spec.md)

**Planning branch**: `agent/planner-lead/38bb392a6f3b`

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**Input**: MY-1818 issue revision 1, Team Lead planning handoff, repository evidence, and shared-telemetry integration contract

## Summary

Adopt the immutable shared-telemetry Azure Blob adapter as a second, explicitly routed product-telemetry path without changing the existing Loki event service or Loki log sink. VoxPocket exposes only two typed product events, rejects non-allowlisted/private data before persistence, and constructs its dedicated retry store/service through a serialized non-`@MainActor` host coordinator only for the interactive app after persisted “Send usage data” opt-in. Consent defaults off; disable stops admission/upload while retaining pending files; first opt-in creates the resettable persisted install UUID. CLI, headless, and test hosts never construct the service. Decision 2A exempts only the SDK-owned internally synchronized off-main heartbeat from that host seam. Decision 1A uses an Owner-created create-only stored-policy container service SAS. Real values enter an Owner-authorized macOS TestFlight archive only through a temporary untracked `0600` runner xcconfig whose path is passed with `-xcconfig`; required CI proves synthetic plist expansion and raw/escaped log absence. Dependency, privacy, app, CI, and TestFlight-governance work ships as independently working single-goal PRs.

## Technical Context

**Language/version**: Swift 6.2 packages/app; Python 3.11+ repository tests; Ruby/Fastlane; YAML/GitHub Actions; XcodeGen

**Primary dependencies**: shared-telemetry/LokiKit exact `0.2.0` (annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5`, peeled commit `903f4b9bc01cfcfeba3ce96e13519d841781b40a`); existing SwiftUI/AppKit app shell; shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`

**Storage**: dedicated Application Support Blob adapter catalog/event/sidecar/capacity files; existing Loki event/log stores remain separate and untouched

**Testing**: Swift Testing/XCTest package and app tests; repository Python/Ruby packaging fixtures; XcodeGen idempotency; unsigned synthetic macOS Release build with processed-plist inspection; policy/layer/full gates

**Target platform**: macOS app and manual macOS TestFlight release; iOS remains compile/test only and receives no TestFlight enablement

**Project type**: layered Swift desktop/mobile app with SwiftPM packages, XcodeGen app shell, and root release/CI support

**Performance goals**: no host synchronous Blob file I/O on `@MainActor`; one serialized host owner for construction/product `track`/lifecycle `flush`; UI/lifecycle submission returns without waiting on file I/O; one active flush maximum; SDK heartbeat remains internally synchronized/off-main

**Constraints**: explicit persisted consent defaults off; no Blob construction in CLI/headless/test hosts; no audio/transcript/refined/prompt/error/credential telemetry; no generic strings; stored-policy service SAS with effective create-only permission; no user-delegation query fields; no value-bearing xcargs/environment/printable arguments; no live Azure CI; no committed real identifier; no implicit release dispatch; no queue migration; disabled/failed/cancelled events stay retryable; no test/gate weakening

**Scale/scope**: three dependency consumers, two current privacy boundaries, one default-off Settings consent/reset surface, one app-lifetime Blob runtime, four closed user-action labels, one performance operation, two plist/build settings, and one Owner-gated release path

## Constitution Check — Before Research

| Principle / repository rule | Result | Plan response |
|---|---|---|
| I Immutability | PASS | Product events are immutable typed values; adapter files change only through the single owner. No existing user data is mutated. |
| II Layer direction | PASS | Infrastructure owns persisted preferences, Presentation owns the Settings view model/UI, Application hardens its telemetry boundary, app-shell composition owns Blob integration/host exclusion, and root support owns CI/release. No package imports the app. |
| III Concurrency safety | PASS | Host construction/product `track`/lifecycle `flush` are isolated in a non-`@MainActor` actor. Main-actor callers submit asynchronously; flushes serialize/join. Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat work. |
| IV Privacy of voice/text | PASS | Exact allowlists and sentinel tests reject voice/text/prompt/error/credential content before accepted state; existing unsafe error fields are removed. |
| V Secrets/vendor hygiene | PASS | No real endpoint/SAS/resource identifier is committed or used in PR tests. Real values enter only through a runner-temp untracked `0600` xcconfig during an authorized TestFlight archive; only its path is printable, cleanup is unconditional, and raw/escaped sentinel absence is tested. |
| VI Boundary validation | PASS | Plist, adapter policy, labels, numeric bounds, exact dependency version/tag integrity, and processed Release output are validated fail-closed. |
| XcodeGen source of truth | PASS | `VoxPocket/project.yml` owns build settings/file membership; generated project changes are produced only by the pinned generator and checked for idempotency. |
| TestFlight-only production delivery | PASS | Local/PR verification is unsigned, synthetic, and non-networked. Production evidence remains post-merge and Owner-authorized. |
| Existing behavior preserved | PASS | Loki services/stores/routing and release semantics remain, except the explicitly authorized removal of arbitrary error strings. |
| Important paths need Owner | PASS | Planning, dependency, app-project, CI, Fastlane, scripts, constitution, architecture, and context changes use their existing per-PR CODEOWNERS gates. No aggregate PR or evidence reuse is allowed. |

No constitutional exception is requested.

## Research Decisions

The evidence and alternatives are in [`research.md`](./research.md). Binding decisions:

1. **R-001 — Immutable repository-wide dependency**: move every consumer, guard, current authority, and current projection together to SwiftPM exact `0.2.0`; record the annotated tag object and peeled commit as integrity evidence only, with no branch or revision fallback.
2. **R-002 — Separate transports and stores**: Blob neither decorates nor mirrors Loki; it owns a dedicated store and must not migrate/delete Loki data.
3. **R-003 — Closed event vocabulary**: typed constructors expose only `product.user_action` and `product.performance`; heartbeat is SDK-owned.
4. **R-004 — Off-main serialized host lifecycle**: one non-`@MainActor` actor is the sole host entry for the exact bundle initializer, product `track`, and lifecycle `flush`; Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat work.
5. **R-005 — Disabled before state**: missing/empty/unexpanded config creates no identity/store/network state; present-invalid config closes only Blob with a fixed diagnostic.
6. **R-006 — Release-only real configuration**: source plist uses build references; PR uses synthetic Release proof; TestFlight writes secrets only into a runner-temp untracked `0600` xcconfig, passes only its path via `-xcconfig`, cleans unconditionally, and proves raw/escaped sentinels absent from logs.
7. **R-007 — Privacy fix at owners**: Application/Infrastructure replace or remove arbitrary error strings and add boundary-specific sentinel regressions.
8. **R-008 — Compatibility first**: preserve Debug/local behavior, manual macOS TestFlight, iOS compile/test-only behavior, signing/build/upload/tag logic, and every existing gate.
9. **R-009 — Owner-gated single-goal PRs**: separate planning, dependency, behavioral/privacy, app, synthetic-CI, and TestFlight-governance changes; do not bypass package/project/workflow/Fastlane/script/constitution/context ownership.
10. **R-010 — External production slice**: Owner provisioning/dispatch and Team Lead read-only blob evidence are separate from implementation completion.
11. **R-011 — Stored-policy service SAS**: Decision 1A uses key-authenticated policy permission `c` plus explicit expiry and an HTTPS-only container service SAS bound with `si`; stored-policy form omits `sp`, while any explicit `sp` must equal `c`.
12. **R-012 — Explicit consent, resettable identity, and excluded hosts**: persist “Send usage data” in `UserDefaults` defaulting off; disable admission/upload without deleting pending files or the persisted UUID; create the random install UUID only on first opt-in, keep pre-opt-in Reset a no-op, retain the UUID inactive while off, reuse it after later opt-in unless Reset replaces it, and keep Reset consent-neutral; never construct Blob telemetry in CLI/headless/test hosts.

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
- In PR05, add a focused telemetry Settings view model and extend `MacOSSettingsView` plus the existing cross-platform `MeRootView` privacy surface with the exact “Send usage data” toggle and install-identity Reset action. The view model uses the Infrastructure preference contract and exposes no endpoint, SAS, UUID value, generic event API, or app-shell dependency.
- Existing Settings pages, full-panel/quick-record behavior, and all other Presentation UI/view-model behavior remain preservation surfaces.

### VoxInfrastructure consent preferences

- In PR04, extend `PreferencesKey`/`UserDefaultsPreferencesStore` with the persisted consent and install-identity records plus focused isolated-suite coverage in `Packages/VoxInfrastructure/Tests/PreferencesTests/ProductTelemetryPreferencesTests.swift`. Consent absence reads as `false`; identity absence remains absence until first opt-in; a created identity persists across disable and remains inactive until later opt-in reuses it or consent-neutral Reset replaces it.
- The preference layer stores values only. It does not import Presentation or the app, construct telemetry, interpret Blob configuration, or perform admission/upload.

### VoxPocketApp Blob runtime

- Add `VoxPocketBlobTelemetry.swift`, `BlobTelemetryConfiguration.swift`, `BlobTelemetryHostEligibility.swift`, and `BlobTelemetryLifecycleCoordinator.swift` under `VoxPocket/VoxPocket/`; add `BlobTelemetryPolicyTests.swift`, `BlobTelemetryConfigurationTests.swift`, `BlobTelemetryConsentTests.swift`, `BlobTelemetryLifecycleCoordinatorTests.swift`, and `BlobTelemetryInstrumentationTests.swift` under `VoxPocket/VoxPocketTests/`; register them only through `VoxPocket/project.yml`.
- The runtime reads exact plist keys and validates disabled/invalid/enabled state, but the interactive app constructs it only after persisted consent is on. Never-opted-in/off creates no service/store or identity and makes no identity-provider request; Reset is a no-op in that state. First opt-in creates a non-personal install UUID. Disabling after opt-in stops the live generation's admission/upload while retaining its pending files, store state, and persisted UUID without active-service identity request/use; a later explicit opt-in and eligible launches reuse that UUID unless Reset replaced it. Reset with an existing UUID while off or on replaces it without enabling or otherwise changing consent and rotates a live generation only while on.
- A non-`@MainActor` actor is the sole host caller of `AzureBlobTelemetryService(bundle:app:build:version:privacy:storeDirectory:isEnabled:identityProvider:configuration:maxDiskBytes:)`, product `track`, and lifecycle `flush`, and performs enabled-service/store construction through actor-isolated asynchronous bootstrap. `ServiceContainer`, `AppDelegate`, and `MacOSAppScenes` schedule typed commands; they never construct an enabled store or call adapter synchronously. Tests admit only the SDK-owned internally synchronized heartbeat exemption.
- The composition boundary classifies the interactive app before service bootstrap. CLI, headless, and test hosts never create the Blob service even when synthetic configuration and preferences are present. The repository has no production CLI target, so CLI/headless behavior is proven by a negative host-kind fixture instead of inventing an executable.
- Record `app_launch` duration and the four accepted actions at successful semantic boundaries. Request flush after startup telemetry, recording/session completion, and macOS resign-active. Join the active flush and retain failed/cancelled pending files.
- Add exact source plist substitutions and synthetic Release settings through `Info.plist`, `Config.xcconfig`, and `project.yml`. Existing Loki construction, injection, event routing, log sink, and stores remain separate.

### Root dependency and release support

- Update all active dependency consumers, guards, authorities, and projections in one dependency-only PR: the three manifests; `scripts/ci/fetch-external-deps.sh`; `scripts/tests/test_app_logging.py`; `AGENTS.md`; `.specify/memory/constitution.md`; `docs/architecture/tech-context.md`; `docs/architecture/packages-architecture.md`; `README.md`; `Packages/VoxInfrastructure/tech-context.md`; `Packages/VoxInfrastructure/OVERVIEW.md`; `Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/README.md`; `VoxPocket/tech-context.md`; `docker/telemetry/README.md`; and the stale dependency comment in `.github/workflows/testflight.yml`. The constitution edit is a deliberate protected amendment naming rule, reason, migration impact, and version metadata; historical baseline statements in this feature's `spec.md`/`research.md` remain unchanged and explicitly historical.
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

## Implementation Slices

### PR00 — Land the reviewed planning package

Land only the exact AI-Reviewer-PASS planning artifacts and Spec Kit pointers before implementation. This PR contains no dependency/product/CI implementation and uses the normal CODEOWNERS path for `CLAUDE.md`.

### PR01 — Dependency-only immutable selection

Validate annotated `v0.2.0` and its peeled commit, run the provider consumer fixture in version mode, then atomically move all three manifests, guards, active authorities/projections, protected constitution amendment, and stale dependency-only workflow comment to exact `0.2.0`. The observable goal is one repository-wide Blob-capable exact selection with no runtime behavior change. This PR is cross-layer but single-goal; every package and repository gate passes at its head.

### PR02 / PR03 — Independent privacy repairs

PR02 removes arbitrary stringified transcription-error telemetry in VoxInfrastructure; PR03 removes localized refinement-error telemetry in VoxApplication. Each contains its own red/green sentinel regression and preserves safe Loki metrics and runtime/UI error behavior. PR01, PR02, and PR03 each depend only on merged PR00 (or an explicitly approved base containing byte-identical reviewed planning artifacts); their owned paths and outputs are independent, so the three PRs may proceed in parallel.

### PR04 — Dormant Blob deep module

After PR01, PR02, and PR03 merge, add the typed policy/configuration/store/coordinator, consent/identity preference state, host-eligibility policy, source plist/XcodeGen settings, and focused tests, but no production call site. Missing/unexpanded source settings or default-off consent keep it unused and disabled. First-opt-in/reuse/reset identity, live disable/re-enable with pending-file retention, CLI/headless/test exclusion, the exact initializer, Decision 2A heartbeat boundary, Decision 1A query fixture, actor ordering, privacy, and disabled/invalid states are independently testable without credentials.

### PR05 — App adoption and instrumentation

Add the Presentation Settings toggle/reset surface, then activate the tested deep module through the interactive app composition in `ServiceContainer`, `AppDelegate`, and `MacOSAppScenes`. Emit only the four closed actions and launch performance event; add retry-safe lifecycle flushes. Default-off/disabled consent and CLI/headless/test hosts construct no Blob service. Opening Settings may retain its existing unrelated local-model access, but it must load consent independently and cannot make Blob construction a side effect. No manifest, CI, Fastlane, or TestFlight secret wiring changes are included. Unconfigured builds remain disabled and existing Loki behavior is preserved.

### PR06 — Synthetic Release CI

Add only the unsigned synthetic Release processed-plist helper, tests, and required CI wiring. Fake non-routable values are used; signing, upload, TestFlight, real secrets, and network senders are excluded.

### PR07 — TestFlight secure injection

Add only the authorized macOS TestFlight temp-`0600`-xcconfig path across workflow/Fastlane/tests/docs. Preserve the manual trigger, signing, numbering, upload, tag behavior, and iOS disablement. This PR alone carries the exact Decision 1A Owner commands and both secret-add commands.

### Production — Owner-controlled evidence

After PR01–PR07 merge, Owner policy/secret provisioning, and fresh Owner release authorization, the existing manual workflow produces one macOS TestFlight build. The tester separately enables “Send usage data” in Settings and performs one approved action; release authorization is not consent. Team Lead records only the build number, run/revision, blob name, and terminal category from read-only evidence.

## Acceptance Traceability

| Acceptance / requirement | Slice | Tasks | Evidence |
|---|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC6; FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-010, FR-011, FR-012, FR-015, FR-021 | PR04/PR05 | T008, T009 | typed contract; exact initializer/heartbeat fixture; coordinator ordering/join/retry; startup/action/flush adoption; unchanged Loki assertions |
| US1/AC5; FR-020; SC-006 | Production | T012 | explicit Owner authorization plus separate tester Settings opt-in; one approved action; exact merged/run revision; TestFlight build number; read-only blob name; no payload/credential evidence |
| US2/AC1; FR-005–FR-008, FR-015 | PR02–PR05 | T006–T009 | whole-event rejection plus Infrastructure/Application/app-shell privacy sentinels |
| US2/AC2; FR-008, FR-009; RB-001 | PR02/PR03 | T006, T007 | red/green localized/stringified-error tests and closed/omitted replacement fields |
| US2/AC3, US2/AC4; FR-010, FR-011 | PR04 | T008 | missing/empty/unexpanded zero-state and present-invalid fixed-diagnostic fixtures |
| US2/AC5; FR-014, FR-015, FR-016, FR-018, FR-019 | PR04/PR06/PR07 | T008, T010, T011 | SAS fixture; synthetic Release; temp-xcconfig/raw+escaped log absence; preserved gates |
| US3/AC1; FR-001 | PR01 | T001–T005 | provider version-mode consumer check; exact `0.2.0`; annotated-tag object/peeled-commit integrity record; matching manifests, guards, authorities/projections; constitution amendment |
| US3/AC2; FR-002, FR-003, FR-008, FR-009 | PR02/PR03/PR05 | T006, T007, T009 | Loki construction/routing/store regressions and privacy-only removals |
| US3/AC3; FR-013, FR-015–FR-017 | PR04/PR06 | T008, T010 | XcodeGen/plist contract and processed synthetic Release app |
| US3/AC4; FR-014, FR-015, FR-016, FR-017, FR-018 | PR07 | T011 | path-only `-xcconfig`; mode/cleanup; raw+escaped absence; unchanged release invariants |
| US3/AC5; FR-018, FR-019; SC-005 | PR00–PR07 | T000–T011 | per-PR one-goal/exact-head evidence and applicable Owner gates; exact commands only in PR07 |
| US1/AC7, US1/AC8, US2/AC6; FR-022–FR-024; SC-007 | PR04/PR05 | T008, T009 | isolated `UserDefaults` consent/identity fixtures; macOS/cross-platform Settings toggle/reset tests; pre-opt-in Reset no-op; disable→off pending-file/UUID retention→later-opt-in UUID reuse; consent-neutral Reset with an existing UUID while off/on; excluded-host zero-construction fixtures |
| SC-001 | PR02–PR05 | T006–T009 | all supplied prohibited sentinels rejected before persistence/transport |
| SC-002 | PR04 | T008 | zero identity-provider/store/enqueue/network calls for disabled Debug/Release fixtures |
| SC-003 | PR06/PR07 | T010, T011 | expanded synthetic plist plus zero raw/escaped sentinels or value-bearing arguments/logs |
| SC-004 | PR01–PR07 | T001–T011 | each PR's focused verification, `scripts/verify`, exact-tree review, and no weakened test |

Every stable acceptance criterion and functional requirement maps to an owned task and evidence surface. RB-001 is the approved arbitrary-error removal; RB-002 preserves separation by forbidding legacy Loki fan-out; RB-003 preserves every other transport, queue, metric, guard, test, signing/upload step, and platform restriction. Production-only acceptance remains explicitly external rather than being claimed by repository tests.

## Verification Strategy

[`quickstart.md`](./quickstart.md) is the executable verification contract. Required implementation evidence:

1. After PR00, PR01 validates annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peeling to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, runs `external_consumer.py --version 0.2.0`, updates the full current-truth path list atomically to exact `0.2.0`, and proves the old selection and every revision selector absent from that list while preserving explicitly historical feature evidence;
2. Independently after PR00 and in parallel with PR01 and each other, PR02 and PR03 each demonstrate their privacy test red against the unsafe baseline, then green without assertion weakening, and pass their own package layer plus `scripts/verify`;
3. Only after PR01, PR02, and PR03 merge, PR04 proves the representative stored-policy query accepted and `sp=cw`/user-delegation/unknown-name forms rejected; it tests the exact bundle initializer, SDK heartbeat exemption, coordinator-only host construction/`track`/`flush`, privacy allowlists, disabled/invalid config, default-off consent, pre-opt-in Reset no-op, first-opt-in UUID creation, disable→off pending-file/UUID retention, later-opt-in UUID reuse unless Reset replaced it, consent-neutral Reset with an existing UUID while off/on, excluded-host policy, actor ordering, joined flush, and retry retention;
4. PR05 proves macOS/cross-platform Settings UI wiring, excluded-host composition, interactive-app consent adoption, app-shell action/lifecycle instrumentation, and unchanged Loki behavior while unconfigured or non-consented builds remain disabled;
5. PR06 generates from `VoxPocket/project.yml`, proves zero generated drift, and inspects an unsigned synthetic Release app's processed plist;
6. PR07 proves the xcconfig is runner-temp/untracked/`0600`, only its path reaches `-xcconfig`, cleanup runs on every terminal path, both raw and escaped sentinels are absent from captured Release logs, and existing manual release invariants remain;
7. every implementation PR passes its focused commands, `scripts/verify`, `git diff --check`, and required CI; PRs forcing full selection also run `scripts/verify --all` locally when practical and rely on the required full CI lanes at the exact head;
8. every PR freezes its own candidate for independent content review before publication, publishes only that tree, and proves equality of local SHA, remote branch OID, and PR `headRefOid`; evidence is never reused across PRs;
9. stacked branches declare their parent; after a prerequisite squash-merges, the child is retargeted/rebased onto `origin/main`, then fully reverified and rereviewed because its SHA changed;
10. production proof occurs only after PR01–PR07 merge, Owner provisioning, a new explicit Owner authorization, and a separate tester opt-in through “Send usage data”; authorization never substitutes for consent.

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
│   └── BlobTelemetryLifecycleCoordinator.swift
└── VoxPocketTests/
    ├── BlobTelemetryPolicyTests.swift
    ├── BlobTelemetryConfigurationTests.swift
    ├── BlobTelemetryConsentTests.swift
    ├── BlobTelemetryLifecycleCoordinatorTests.swift
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

**Structure decision**: PR01 is one atomic cross-layer dependency-selection goal whose layer-scoped tasks update all consumers and current truth/projections; PR02/PR03 own privacy behavior separately. PR01, PR02, and PR03 are independent siblings after PR00 and may run concurrently; PR04 waits for all three and owns the dormant consent-capable deep module plus Infrastructure preference state. PR05 is one vertical adoption goal across Presentation Settings and VoxPocketApp composition; those paths do not overlap PR04. Root support splits synthetic CI (PR06) from TestFlight secret governance (PR07). Generated Xcode project files are outputs, never hand-edited sources.

## Constitution Check — After Design

PASS with no constitutional exception. PR01 deliberately amends only the immutable dependency fact while preserving every constitutional red line and updating its projections atomically. The design preserves package direction, makes every host construction/product `track`/lifecycle `flush` boundary structurally non-main, defaults consent off at the preference/app-composition boundary, excludes non-interactive hosts before construction, narrowly records Decision 2A for SDK-owned heartbeat, rejects private/free-form data before accepted state, uses synthetic credential-free CI, keeps XcodeGen authoritative, isolates Blob files from Loki, and separates Owner-controlled release evidence from implementation authority. The authorized arbitrary-error removal is explicit and test-covered; every other legacy/release behavior remains a preservation surface.

## Dependencies and External Gates

- Repository base: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`.
- Repo contract: shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`.
- Provider dependency: shared-telemetry exact `0.2.0`; annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peels to reviewed commit `903f4b9bc01cfcfeba3ce96e13519d841781b40a`. Those OIDs are integrity evidence, not revision selectors.
- Planning gate: AI Reviewer exact-revision PASS before Team Lead implementation dispatch.
- Per-PR candidate gate: AI Reviewer exact frozen-tree PASS plus explicit publication permission before each commit/push/PR; a changed or rebased SHA is reviewed again.
- Important-path gate: applicable Owner approval and required checks on each exact non-Draft PR head.
- Production gate: PR01–PR07 merged; Owner-created create-only stored policy/container service SAS; both GitHub secrets; a new explicit Owner authorization before manual TestFlight dispatch; then a separate tester Settings opt-in before the approved action used for evidence.

## Risks and Escalation Conditions

| Risk | Mitigation / escalation |
|---|---|
| `v0.2.0` is missing, moved, not annotated, or peels to a commit other than `903f4b9bc01cfcfeba3ce96e13519d841781b40a` | Block PR01 and escalate the exact tag evidence. Do not fall back to a branch or revision selector; ordinary later movement of provider `main` is irrelevant. |
| SDK API differs from reviewed docs | Stop and return exact compiler/provider-contract evidence; do not invent an adapter wrapper or widen shared-telemetry scope. |
| Stored-policy SAS query differs | Compare the synthetic query-name fixture against the pinned validator. Reject user-delegation keys or `sp=cw`; do not broaden the provider or generate a real token. |
| Synchronous host I/O leaks onto `@MainActor` | Structural typed coordinator seam plus actor/order tests. Any direct host construction/product `track`/lifecycle `flush` from UI/lifecycle code blocks review; SDK heartbeat remains only the Decision 2A exemption. |
| Consent or host exclusion is bypassed | Central composition classification plus isolated preference/UI/app fixtures. Any eager identity/service creation, off-state admission/upload, implicit resume, pending-file deletion, or CLI/headless/test construction blocks review. |
| Privacy policy requires arbitrary strings | Reject the event or add a new Owner-approved closed label. Never sanitize/redact after persistence. |
| Store lease/capacity/rollback behavior is incompatible | Preserve all files, stop the Blob owner, and return exact adapter evidence. Never reuse/delete Loki or Blob persisted state manually. |
| XcodeGen produces unexpected drift | Stop with generator version and diff. Do not hand-edit the generated project or absorb unrelated output. |
| Synthetic Release proof needs signing/network | Treat as a design failure and return to the app/root-support owner; do not introduce secrets or live access. |
| Secret or sentinel value appears in logs/arguments/tests/diff | Stop publication, rotate if real, remove the exposure through the owning release seam, and rerun raw-plus-escaped absence evidence. Masking alone is not acceptance. |
| Important approval/check is missing | Keep the PR unmerged in Owner review; never bypass CODEOWNERS/ruleset protection. |
| Owner has not provisioned/authorized production, or tester consent is absent | Repository delivery may complete, but T012 remains blocked; no workflow is dispatched without Owner authority and no telemetry action/blob evidence is attempted without separate tester opt-in. |

## Complexity Tracking

No constitutional violation is requested. The PR01 constitution amendment changes the selected immutable dependency fact, not a red line, and records rule/reason/migration impact with matching projections. The additional actor/runtime is justified by the provider's synchronous persistence boundary and deepens the app interface: callers submit two typed event variants and lifecycle commands without knowing configuration, identity, store, policy, transport, or SDK heartbeat details.
