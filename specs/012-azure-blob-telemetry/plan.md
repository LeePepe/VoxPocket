# Implementation Plan: Privacy-safe Azure Blob product telemetry

**Feature**: `012-azure-blob-telemetry` | **Date**: 2026-10-15 | **Spec**: [`spec.md`](./spec.md)

**Planning branch**: `agent/planner-lead/my-1836-xcodegen-plan`

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**T009 repair base**: `df80dd59b4486dbffabf3ec440be885906c964ef`; historical execution binding `142113c0931aa52951ecd070c27d064608e8215d` / manifest `0b8c278af6539641baf15321775e4a374355adeb3f3911266424608e44a948f4`

**T009 placement correction**: accepted planning revision `ad2d7739d4ee2776997b92c8de8221cd5d9140aa` / manifest `dc57098944b2f76755b6bba996a796da683ab0e053643514ad7ea648e649056e`; registered product candidate `46c389b32812f644a8f56a6b142bd58979f5e58f` on PR #115; current `main` `cd9ccf42fbd11d6fb523546a14dcfe6f8b63e12f`; Lead decision `01a146dc-6965-74bf-aa43-3a6caeacb649`

**T009 test-assembly correction**: accepted placement revision `bd6beb9d5a0ecdccfe786621653beb8320083e4a` / manifest `bef51826141fb1e5918736bf08b4a45ded25d05b6947d611fb5e5ccfe6f67b32`; remote PR #115 head `bef8843f612955bba416485331f426c487e78c08`; preserved local evidence candidate `d3c943d785e7de4c9f923891c631b367e3097a01`; current `main` `fad1e1c8b8081e1957f58c6b8c7ee972aec15f15`; Lead decision `r7notif1 = B` and Team Lead handoff `01a1479f-462f-7f01-8324-ade6b51608a1`

**T009 Round 7 repair input**: merged reviewed planning revision `d8e6849dad17e486b7c484fad31f47ef0beabb6b` / manifest `b1b5e1b9521227a8f42f47b7c2f82a9c8172d628abffa6b14ede8cf5fd6be73a`; live base `2e67d12cb866e56279540e7240b7f6fb3ab8a7ba`; frozen failed candidate `107a75ad141bf6d4d1f60bb686705ced1c5eac5e` / tree `4201cb90c20f5d6630faf5731b6810525849b807`; Round 7 verdict `01a14804-f973-7e9e-8c83-043108402811` (`NEEDS_WORK`, P1=4, missed=3); Lead choice `r7scope1 = A-planning-only` and Team Lead handoff `01a1480b-4b74-71a6-98b8-312764b2ffd8`

**T009 XcodeGen-contract correction input**: merged reviewed planning revision `ec46876cb162a37cf396e1bf4deee94a5786f214` / manifest `008f7a38afb34aad8d839a43a1bbfc174c45429deae37e0d497b76746e09cf31`; live base `ee17eaba54c8f7ad18b85151f04429ba0250b30e`; frozen product work and registered PR #115 remain outside this planning workspace; Lead decision `01a14849-0e8e-7be9-ad7b-2249d82d1abc` and Team Lead handoff `01a1484a-1d14-7bb2-ab0f-b7b6f3db9b1e`

**Input**: MY-1818 issue revision 1, Team Lead planning handoffs, accepted planning manifest `f53efb4cf06d101fb39c4277fa39b4b8b7e3a10ec17a052e4a435a3485bc3ad1`, repository/provider evidence, all preserved Round 1–7 implementation-review/CI history, the 2026-10-16 Lead decision `loki02v1` / `atomic-0.2.0-offmain-plan`, the accepted T009 placement/test-assembly corrections above, the bounded Round 7 planning repair, and the raw XcodeGen-output correction input

## Summary

Adopt immutable shared-telemetry exact `0.2.0` and its Azure Blob adapter while preserving legacy Loki endpoint/routing/log-sink semantics. PR01 first adds the required app-test CI gate. PR02 is then one atomic single-goal exact-`0.2.0`/off-main migration: it combines T005 with every T002–T004/T013 consumer, guard, authority, and current-truth projection, and places every legacy Loki provider construction/`track`/`flush` behind one app-lifetime serialized non-`@MainActor` coordinator. There is no standalone PR03 or reviewed intermediate state that claims an enqueue barrier on `0.1.0`. Exact `0.2.0` makes the boundary real because `LokiTelemetryService.track` synchronously calls `TelemetryQueue.enqueue` and completes its atomic persistence attempt or retained-memory fallback before returning; the coordinator does not begin a later underlying flush until that earlier call returns. The later consented Blob path extends that same coordinator instead of creating a second executor. VoxPocket accepts the provider's default 50 MiB persisted-data cap, whole-oldest-batch eviction, oversized-event rejection, durable loss accounting, and capacity-aware rollback with no `maxDiskBytes` override. The Blob path remains separately routed, exposes only two typed product events, rejects non-allowlisted/private data before persistence, and constructs its dedicated retry store/service only for the interactive app after persisted “Send usage data” opt-in. Consent defaults off; its Settings write is identity-free; only eligible interactive-app composition with valid configuration provisions the app-lifetime UUID; disable stops admission/upload while retaining non-evicted pending files and any UUID, with no v1 Reset surface. CLI, headless, and test hosts never provision identity or construct Blob. Decision 2A exempts only the SDK-owned internally synchronized off-main heartbeat from the host seam. Decision 1A uses an Owner-created create-only stored-policy container service SAS. Real values enter an Owner-authorized macOS TestFlight archive only through a temporary untracked `0600` runner xcconfig whose path is passed with `-xcconfig`; required CI proves synthetic plist expansion and raw/escaped log absence. Governance/CI, the atomic dependency/runtime migration, privacy, app, synthetic CI, and TestFlight work ship as independently working single-goal PRs.

### Decision-bounded canonical delta

Lead decision `loki02v1` originally authorized edits only to canonical `spec.md`, `plan.md`, and `tasks.md`; its old-topology override remains binding. The MY-1836 Team Lead repair direction in comment `01a1456f-f095-73f7-92d1-a794da311e3e`, accepted by Lead note `01a14571-6e7a-710b-9c50-793b02faf28f`, additionally authorized the minimum cross-artifact correction represented by accepted revision `ad2d7739d4ee2776997b92c8de8221cd5d9140aa`. Lead decision `01a146dc-6965-74bf-aa43-3a6caeacb649` corrected the T009 placement defect in accepted revision `bd6beb9d5a0ecdccfe786621653beb8320083e4a`: the sole consent/identity/activation policy owner moved into existing `VoxApplication/UseCases`, while Preferences remained value storage and `VoxPocketApp` remained assembly/platform wiring. Lead decision `r7notif1 = B` produced reviewed revision `d8e6849dad17e486b7c484fad31f47ef0beabb6b`, now merged byte-for-byte in all eight artifacts on live main. Lead choice `r7scope1 = A-planning-only` produced reviewed revision `ec46876cb162a37cf396e1bf4deee94a5786f214`, now merged byte-for-byte on live main, for Round 7's four P1 findings: checked/unchecked Sendable state, structural limits, independently stimulated provider loading, and a real launched `AppDelegate` resign-active FIFO proof. Lead decision `01a14849-0e8e-7be9-ad7b-2249d82d1abc` now authorizes only the minimum `plan.md` / `tasks.md` / `quickstart.md` correction from repository-pinned/idempotent generation assumptions to a selected raw-output and bounded UUID-equivalence contract; the other five accepted artifacts stay byte-identical. Every accepted implementation path, end-state, privacy, compatibility, provider/tag/capacity, release, gate, and prohibition remains unchanged. The registered MY-1836 workspace/candidates and all Round 1–7 verdict/CI history remain cumulative evidence, not execution authority; no product mutation, Round 8, implementation review, publication, CI rerun, approval, merge, or release occurs during planning, and an independent planning PASS plus fresh Team Lead execution permission are required before implementation.

## Technical Context

**Language/version**: Swift 6.2 packages/app; Python 3.11+ repository tests; Ruby/Fastlane; YAML/GitHub Actions; XcodeGen

**Primary dependencies**: shared-telemetry/LokiKit exact `0.2.0` (annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5`, peeled commit `903f4b9bc01cfcfeba3ce96e13519d841781b40a`); existing SwiftUI/AppKit app shell; shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`

**Storage**: existing Loki event store plus a dedicated Application Support Blob adapter catalog/event/sidecar/capacity store; both accept the provider-default 50 MiB persisted-data cap and loss ledger, remain separate from each other and from the independent Loki log-sink queue, and receive no consumer `maxDiskBytes` override

**Testing**: Swift Testing/XCTest package and app tests, including a required macOS app-unit-test CI invocation for the legacy off-main regression, adjacent/intervening flush cases, and an exact-`0.2.0` actual-adapter enqueue-return barrier fixture; repository Python/Ruby packaging fixtures; XcodeGen raw-generation provenance, byte equality to one selected untouched output, and bounded UUID-reference equivalence; unsigned synthetic macOS Release build with processed-plist inspection; policy/layer/full gates

**Target platform**: macOS app and manual macOS TestFlight release; iOS remains compile/test only and receives no TestFlight enablement

**Project type**: layered Swift desktop/mobile app with SwiftPM packages, XcodeGen app shell, and root release/CI support

**Performance goals**: no synchronous legacy Loki or Blob file I/O on `@MainActor`; one serialized app-lifetime coordinator for every underlying provider construction/`track`/`flush`; UI/lifecycle submission returns without waiting on file I/O; flush follows prior admission and one active flush exists at most; SDK heartbeat remains internally synchronized/off-main

**Constraints**: explicit persisted consent defaults off; no Blob construction in CLI/headless/test hosts; no audio/transcript/refined/prompt/error/credential telemetry; no generic strings; stored-policy service SAS with effective create-only permission; no user-delegation query fields; no value-bearing xcargs/environment/printable arguments; no live Azure CI; no committed real identifier; no implicit release dispatch; no queue-format migration or manual deletion; no `maxDiskBytes` override; capacity-aware rollback completes pending eviction cleanup before any older reader; disabled/failed/cancelled non-evicted events stay retryable; no test/gate weakening

**Scale/scope**: three dependency consumers, two current privacy boundaries, one default-off Settings consent surface, one app-lifetime Blob runtime and persisted install UUID, four closed user-action labels, one performance operation, two plist/build settings, and one Owner-gated release path

## Constitution Check — Before Research

| Principle / repository rule | Result | Plan response |
|---|---|---|
| I Immutability | PASS | Product events are immutable typed values; adapter files change only through the single owner. No existing user data is mutated. |
| II Layer direction | PASS | Infrastructure owns persisted values, Presentation owns the Settings view model/UI, Application owns the single consent/identity/activation policy module, app-shell composition owns validated host/configuration facts plus Blob/coordinator/platform adapters, and root support owns CI/release. The existing `VoxPocketApp → VoxApplication → VoxInfrastructure` direction remains downward; no package imports the app. |
| III Concurrency safety | PASS | Atomic PR02 selects exact `0.2.0` and routes every legacy Loki construction/`track`/`flush` through the serialized non-main lifecycle coordinator in the same checked head. Exact `0.2.0` synchronous enqueue completion supplies the barrier input that `0.1.0` could not; only admission-adjacent flushes join, while an intervening track requires a later underlying flush. Later Blob construction/product `track`/lifecycle `flush` extends the same coordinator. Main-actor callers submit asynchronously. Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat work. |
| IV Privacy of voice/text | PASS | Exact allowlists and sentinel tests reject voice/text/prompt/error/credential content before accepted state; existing unsafe error fields are removed. |
| V Secrets/vendor hygiene | PASS | No real endpoint/SAS/resource identifier is committed or used in PR tests. Real values enter only through a runner-temp untracked `0600` xcconfig during an authorized TestFlight archive; only its path is printable, cleanup is unconditional, and raw/escaped sentinel absence is tested. |
| VI Boundary validation | PASS | Plist, adapter policy, labels, numeric bounds, exact dependency version/tag integrity, and processed Release output are validated fail-closed. |
| XcodeGen source of truth | PASS | `VoxPocket/project.yml` owns build settings/file membership. Use the existing repository generation entry without installing or upgrading XcodeGen, record the actual command/version, and require the tracked project to equal one selected untouched raw output; generator reruns may mint new internal UUIDs and are not an idempotency contract. |
| TestFlight-only production delivery | PASS | Local/PR verification is unsigned, synthetic, and non-networked. Production evidence remains post-merge and Owner-authorized. |
| Existing behavior / compatibility | PASS | Loki endpoint/Noop/routing/log-sink/release semantics remain. The Lead explicitly approves two bounded changes: provider work moves off caller/main thread through one serialized coordinator, and provider-default 50 MiB eviction/rollback semantics replace unbounded-retention assumptions. Arbitrary error strings are separately authorized for removal. |
| Important paths need Owner | PASS | Planning, CI governance, atomic runtime/dependency/current-truth migration, app-project, Fastlane, scripts, constitution, architecture, and context changes use their existing per-PR CODEOWNERS gates. Atomic PR02 records the Owner-approved one-time `loki02v1` repository-contract deviation in the protected constitution, keeps only its pointer under `AGENTS.md` Red lines, retains `owner-review`, and requires fresh Owner approval on its final checked head. No evidence reuse is allowed. |

No constitutional exception is requested. Separately, `loki02v1` is the Owner-approved one-time deviation from the repository contract's normal separation of dependency/pin, non-trivial adaptation, and governance change kinds. Atomic PR02 must record that narrow deviation in the existing CODEOWNERS-protected constitution and replace `AGENTS.md`'s current “Approved exceptions: none” Red-lines entry with a pointer to the protected record; neither location may generalize the exception.

## Research Decisions

The provider evidence and alternatives are in [`research.md`](./research.md). Its old PR02-then-PR03 sequencing statements are preserved as reviewed historical evidence but are superseded by Lead decision `loki02v1`; the canonical execution graph is this plan plus `tasks.md`. Binding decisions:

1. **R-001 — Immutable repository-wide dependency**: move every consumer, guard, current authority, and current projection together with the legacy coordinator adaptation in atomic PR02 to SwiftPM exact `0.2.0`; record the annotated tag object and peeled commit as integrity evidence only, with no branch or revision fallback.
2. **R-002 — Separate transports and stores**: Blob neither decorates nor mirrors Loki; it owns a dedicated store and must not migrate/delete Loki data.
3. **R-003 — Closed event vocabulary**: typed constructors expose only `product.user_action` and `product.performance`; heartbeat is SDK-owned.
4. **R-004 — One off-main serialized telemetry lifecycle with a real enqueue barrier**: atomic PR02 selects exact `0.2.0` while introducing one app-lifetime non-`@MainActor` coordinator as the sole underlying caller for every legacy Loki construction, `track`, and `flush`; all existing injected callers retain only its `TelemetryService` facade. Exact `0.2.0` calls `TelemetryQueue.enqueue` synchronously, so the atomic persistence attempt or retained-memory fallback finishes before provider `track` returns. The serial coordinator uses that real return boundary before beginning any later underlying flush, preserves admission order, joins only adjacent flushes, and executes a follow-up flush when an intervening track precedes a later flush request. A synchronous fake proves scheduling/concurrency but cannot by itself prove the adapter enqueue barrier; an exact-`0.2.0` `LokiTelemetryService` with isolated storage must participate in the regression. PR06 extends this same seam for Blob bundle construction, product `track`, and lifecycle `flush`; Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat work.
5. **R-005 — Disabled before state**: missing/empty/unexpanded config creates no identity/store/network state; present-invalid config closes only Blob with a fixed diagnostic.
6. **R-006 — Release-only real configuration**: source plist uses build references; PR uses synthetic Release proof; TestFlight writes secrets only into a runner-temp untracked `0600` xcconfig, passes only its path via `-xcconfig`, cleans unconditionally, and proves raw/escaped sentinels absent from logs.
7. **R-007 — Privacy fix at owners**: Application/Infrastructure replace or remove arbitrary error strings and add boundary-specific sentinel regressions.
8. **R-008 — Compatibility first**: preserve Debug/local usability, endpoint/Noop/routing/log-sink semantics, manual macOS TestFlight, iOS compile/test-only behavior, signing/build/upload/tag logic, and every existing gate, except for the explicitly approved legacy off-main execution and provider-default bounded-retention changes.
9. **R-009 — Owner-gated single-goal PRs**: separate planning, required-CI governance, the atomic exact-`0.2.0`/off-main migration, behavioral/privacy, app, synthetic-CI, and TestFlight-governance changes. The Lead-selected atomic migration intentionally combines non-trivial runtime adaptation with its inseparable dependency/current-truth and governance projections to eliminate the impossible old-`0.1.0` contract. This is a one-time Owner-approved deviation from repository-contract change-kind separation, so the final tree records `loki02v1` in the protected constitution and keeps only its pointer under `AGENTS.md` Red lines. It retains one goal, one writer, `owner-review`, and fresh Owner approval on the final checked head. Do not bypass package/project/workflow/Fastlane/script/constitution/context ownership or extend the deviation.
10. **R-010 — External production slice**: Owner provisioning/dispatch and Team Lead read-only blob evidence are separate from implementation completion.
11. **R-011 — Stored-policy service SAS**: Decision 1A uses key-authenticated policy permission `c` plus explicit expiry and an HTTPS-only container service SAS bound with `si`; stored-policy form omits `sp`, while any explicit `sp` must equal `c`.
12. **R-012 — Explicit consent, app-lifetime identity, and excluded hosts**: persist “Send usage data” in `UserDefaults` defaulting off through an identity-free interface; missing/invalid configuration and excluded hosts retain that choice without identity. `VoxApplication/UseCases` owns the sole consent/identity/activation policy, and only after the app supplies eligible interactive-host plus valid-configuration facts may that policy request the random install UUID. Disable admission/upload without host/manual deletion, retain non-evicted pending files and the persisted UUID inactive while off, and reuse the same UUID after later opt-in and eligible launches for the app installation's lifetime; expose no v1 install-ID Reset/rotation surface, require no shared-telemetry API change or private-storage parsing, and never provision identity or construct Blob telemetry in CLI/headless/test hosts.
13. **R-013 — Accept provider capacity defaults and rollback contract**: pass no `maxDiskBytes` override to legacy Loki or Blob. Accept the pinned provider `ai/MIGRATION.md` default of 50 MiB for persisted source JSON/Blob sidecars, whole-oldest-batch eviction, oversized-event rejection, and durable dropped-event accounting. Before downgrade, stop producers and use the `0.2.0` capacity-aware reader to finish pending paired eviction cleanup after storage is writable; preserve the loss ledger and retained files, never overlap old/new writers, and treat already evicted events as unrecoverable.
14. **R-014 — Selected raw XcodeGen output with bounded reference equivalence**: keep `VoxPocket/project.yml` byte-identical, invoke the repository's existing generation entry with the installed XcodeGen, and record the actual command and `xcodegen --version` without treating that observation as a repository pin or installing/upgrading the generator. The final tracked `project.pbxproj` is byte-identical to one selected untouched raw output. In addition to the two new Swift memberships, a complete tracked-base-to-raw comparison permits only one-to-one, collision-free UUID renames of the existing `Config.xcconfig` `PBXFileReference` and its config-only `VoxPocket` `PBXGroup`; the comparison maps identifiers only in memory, traverses every declaration and reference, and requires complete equality after those two mappings. Reruns may mint different UUIDs, so each selected output needs fresh proof and no rerun is described as idempotent or zero-diff.

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

### VoxApplication consent/identity/activation policy seam

- The T009 correction adds `ProductTelemetryActivationUseCase` and `DefaultProductTelemetryActivationUseCase` together in `Packages/VoxApplication/Sources/UseCases/ProductTelemetryActivationUseCase.swift`; package-interface tests live in `Packages/VoxApplication/Tests/UseCasesTests/ProductTelemetryActivationUseCaseTests.swift`. This replaces the policy state machine currently embedded in the registered candidate's app-shell `ProductTelemetryRuntime`; it does not layer a second state machine over it.
- The public `@MainActor` interface owns consent-transition generations, ordered Boolean persistence, startup deferral behind an overlapping explicit transition, stale-activation rejection, waiter termination, and the single readiness fact that gates product record/flush admission. Its narrow operations are `beginConsentTransition(_:isEligible:)`, `activateAtStartupIfEligible(_:)`, `waitForPendingTransition()`, and read-only `isReady`; consent/eligibility parameters are neutral `Bool` values and the asynchronous transition handle remains product-specific rather than exposing Blob types.
- `DefaultProductTelemetryActivationUseCase` receives only product-specific typed `@Sendable` async closures/adapters for reading consent, persisting the Boolean, provisioning/reusing an identity, activating with a `UUID`, and disabling, plus neutral `Bool`/`UUID` values. It checks the caller-supplied eligibility fact before invoking identity provisioning, and it accepts activation success only for the latest intent. The activation checkpoint and pending-transition awaiter remain package-internal DEBUG seams used only by `@testable import UseCases`; no public checkpoint type/initializer or App-shell forwarding overload remains.
- The interface never imports `VoxPocketApp`, exposes app-private `BlobTelemetryConfiguration`, `BlobTelemetryBootstrap`, coordinator/event types, SAS, endpoint, credentials, or adds a generic telemetry interface, controller, worker, or executor. The existing package edge `VoxApplication → VoxInfrastructure` remains unchanged; `VoxPocketApp` assembly adapts Preferences behind the injected product-specific closures, so the Application interface imports no Preferences or app type and needs no `Package.swift` change or new dependency.

### VoxPresentation dependency boundary

- Move `Packages/VoxPresentation/Package.swift` to the same immutable selection.
- In PR07, add a focused telemetry Settings view model and extend `MacOSSettingsView` plus the existing cross-platform `MeRootView` privacy surface with the exact “Send usage data” toggle. The view model uses the Infrastructure preference contract and exposes no endpoint, SAS, UUID value, generic event API, app-shell dependency, or install-ID Reset/rotation action.
- Existing Settings pages, full-panel/quick-record behavior, and all other Presentation UI/view-model behavior remain preservation surfaces.

### VoxInfrastructure consent preferences

- In PR06, extend `PreferencesKey`/`UserDefaultsPreferencesStore` with the persisted consent and install-identity records plus focused isolated-suite coverage in `Packages/VoxInfrastructure/Tests/PreferencesTests/ProductTelemetryPreferencesTests.swift`. Consent absence reads as `false`; its accepted coupled provisioning interface can create identity, and a created identity persists across disable, remains inactive while off, and is reused after every later opt-in and eligible launch for the app installation's lifetime. The accepted T009 candidate adds the identity-free Settings persistence route without changing that T008 behavior.
- The accepted T009 candidate already adds the narrow `ProductTelemetryPreferences.persistConsent(_:)` interface in `Packages/VoxInfrastructure/Sources/Preferences/PreferencesStore.swift` and proves it in `Packages/VoxInfrastructure/Tests/PreferencesTests/ProductTelemetryPreferencesTests.swift`. It serializes with the existing mutation chain and writes only the Boolean; it never reads, requests, creates, or returns install identity. Preserve the accepted T008 `setConsent(true) -> UUID?` and `installIdentityIfConsented()` behavior and every existing T008 test. The placement/test-assembly corrections do not edit either Infrastructure path: its consent-write gate initializer remains internal DEBUG package-test support, is exercised only through `@testable import Preferences`, and is never called by `VoxPocketTests` or another ordinary-import consumer. The Application policy calls the accepted value-storage adapters, and only after eligibility is true may it call the existing identity-provisioning adapter.
- The preference layer stores values only. It does not import Presentation or the app, construct telemetry, interpret Blob configuration, or perform admission/upload.

### VoxPocketApp shared telemetry lifecycle and Blob runtime

- In PR01 add only the required macOS App-target CI step that runs the existing `VoxPocketTests` target after XcodeGen, so the later regression will be executed rather than merely compiled.
- In atomic PR02 add `TelemetryLifecycleCoordinator.swift` under `VoxPocket/VoxPocket/` and `TelemetryLifecycleCoordinatorTests.swift` under `VoxPocket/VoxPocketTests/` in the same final tree that selects exact shared-telemetry `0.2.0`. `ServiceContainer` retains only the coordinator-backed `TelemetryService` facade and injects that facade into every existing App/Presentation/Application/Infrastructure caller. The coordinator lazily constructs the selected legacy provider on its dedicated serial non-main executor and is the only object allowed to invoke underlying legacy `track`/`flush`; it keeps admission FIFO, joins only adjacent flushes, and runs a follow-up underlying flush when an intervening track precedes a later flush request. Exact `0.2.0` `track` synchronously completes `TelemetryQueue.enqueue`'s atomic persistence attempt or retained-memory fallback before return, so the serial coordinator uses that return as the barrier before starting a later underlying flush. A main-actor-originating factory/spy proves off-main execution, FIFO, adjacent joining, the intervening-admission follow-up, and maximum concurrency one. Separately, an actual exact-`0.2.0` `LokiTelemetryService` configured with an isolated temporary store sits behind a test-only boundary recorder; the regression asserts the real adapter's `track` return is observed before the later underlying `flush` entry. The synchronous fake is not accepted as the sole enqueue-barrier proof. Whenever generation is required, the tracked Xcode project must follow R-014's selected raw-output provenance and bounded equivalence contract.
- In PR06 extend that same `TelemetryLifecycleCoordinator.swift` for Blob lifecycle rather than adding a second executor; add `VoxPocketBlobTelemetry.swift`, `BlobTelemetryConfiguration.swift`, and `BlobTelemetryHostEligibility.swift` under `VoxPocket/VoxPocket/`; add `BlobTelemetryPolicyTests.swift`, `BlobTelemetryConfigurationTests.swift`, and `BlobTelemetryConsentTests.swift` under `VoxPocket/VoxPocketTests/`; register them only through `VoxPocket/project.yml`. PR07 adds `BlobTelemetryInstrumentationTests.swift` with the production adoption it verifies.
- The app reads exact plist keys, validates disabled/invalid/enabled state, classifies the host, and passes only the combined eligibility fact plus narrow necessary operations to `ProductTelemetryActivationUseCase`. Never-opted-in/off, missing/invalid configuration, and excluded hosts create no service/store or identity and make no identity-provider request. The Application policy requests the first non-personal install UUID only after explicit opt-in and an eligible interactive-app fact. Disabling after opt-in stops the live generation's admission/upload without host/manual deletion while retaining non-evicted pending files, capacity ledger state, and the persisted UUID without active-service identity request/use; every later explicit opt-in and eligible launch reuses that same UUID for the app installation's lifetime. V1 exposes no install-ID Reset/rotation action, makes no shared-telemetry interface change for identity lifecycle, and does not parse adapter-private storage or catalog state.
- The same non-`@MainActor` coordinator becomes the sole host caller of the `AzureBlobTelemetryService` bundle initializer, omitting `maxDiskBytes` to accept the provider default, plus product `track` and lifecycle `flush`; enabled-service/store construction occurs through isolated asynchronous bootstrap. `ServiceContainer`, `AppDelegate`, and `MacOSAppScenes` schedule typed commands; they never construct an enabled store or call either provider synchronously. Tests admit only the SDK-owned internally synchronized heartbeat exemption.
- The composition boundary classifies the interactive app before service bootstrap. CLI, headless, and test hosts never create the Blob service even when synthetic configuration and preferences are present. The repository has no production CLI target, so CLI/headless behavior is proven by a negative host-kind fixture instead of inventing an executable.
- `ServiceContainer` assembles the Application use case with closures that keep configuration, bootstrap, coordinator, and event conversion app-private; `ProductTelemetryInstrumentation` becomes platform wiring with no consent/identity policy state. Its existing defaulted app-owned `NotificationCenter` assembly input is the only App-test isolation seam. App tests construct `ProductTelemetrySettingsViewModel` through the existing public `preferences:onConsentChanged:` initializer and adapt that closure to the same private center; they do not consume a package-internal notification-center initializer, Preferences write gate, or Application activation checkpoint. Record `app_launch` duration and the four accepted actions at successful semantic boundaries. Request flush after startup telemetry, recording/session completion, and macOS resign-active. Join the active flush; failure/cancellation causes no host/manual deletion, and non-evicted pending files remain retryable.
- Add exact source plist substitutions and synthetic Release settings through `Info.plist`, `Config.xcconfig`, and `project.yml`. Loki endpoint/Noop selection, event routing, and log sink remain separate; the only shared seam is the already-reviewed non-main lifecycle coordinator.

### Root dependency and release support

- In atomic PR02, update all active dependency consumers, guards, authorities, and exact-version projections together with the coordinator adaptation: the three manifests; `scripts/ci/fetch-external-deps.sh`; the dependency assertions in `scripts/tests/test_app_logging.py`; `AGENTS.md`; `.specify/memory/constitution.md`; `docs/architecture/tech-context.md`; `docs/architecture/packages-architecture.md`; `README.md`; `Packages/VoxInfrastructure/tech-context.md`; `Packages/VoxInfrastructure/OVERVIEW.md`; `Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/README.md`; `VoxPocket/tech-context.md`; `docker/telemetry/README.md`; and the stale dependency comment in `.github/workflows/testflight.yml`. The constitution edit is a deliberate protected dependency-fact amendment naming rule, reason, migration impact, and version metadata; historical baseline statements in this feature's `spec.md`/`research.md` remain explicitly historical. Required-CI wiring stays in PR01. No separate PR03 is published.
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

- Exact `0.2.0` `LokiTelemetryService.track` calls `TelemetryQueue.enqueue` synchronously; its atomic persistence attempt or retained-memory fallback completes before `track` returns. Atomic PR02 places all legacy construction/`track`/`flush` work behind the single serialized non-main coordinator in the same checked head. Therefore an earlier provider `track` return is a real barrier input before a later underlying `flush` begins. The old `0.1.0` return only launched an unstructured enqueue task and could not satisfy that contract. Endpoint/token selection, safe event vocabulary, receiver, and flush triggers remain; caller-thread execution and immediate direct invocation do not.
- VoxPocket passes no `maxDiskBytes` override to either legacy Loki or Blob construction. The accepted provider default is 50 MiB of persisted source JSON plus Blob sidecars, excluding memory fallback, ledger metadata, and atomic-write transients. Whole oldest batches may be evicted, an oversized event may be rejected, and durable `droppedEventCount`/loss tombstones record loss. Already evicted events are unrecoverable.
- Rollback is capacity-aware: stop producers and active work, prevent old/new writer overlap, make the store writable, and let the `0.2.0` reader finish any pending paired eviction cleanup before a separately reviewed older reader opens the store. Preserve the loss ledger and retained files; otherwise an older reader can replay logically dropped files. Do not manually delete/convert files or claim provider migration notes as a product old→new→old drill.
- Release builds without `LOKI_ENDPOINT` still select `NoopTelemetryService`, so active legacy persistence/capacity impact is limited to Debug/local logging or an explicitly configured Release receiver. This rationale does not waive the executor or rollback contract.

## Implementation Slices

### PR00 — Land the reviewed planning package

Land only the exact AI-Reviewer-PASS planning artifacts and Spec Kit pointers before implementation. This PR contains no dependency/product/CI implementation and uses the normal CODEOWNERS path for `CLAUDE.md`.

### PR01 — Required app-unit-test CI gate

Add only the required macOS App-target `VoxPocketTests` invocation after the existing XcodeGen step. Current tests pass with signing disabled; no product code, test, dependency selector, constitution, architecture, or current-truth document changes.

### PR02 — Atomic exact 0.2.0 / off-main legacy migration

Combine T005 with all of T002–T004/T013 in one single-goal candidate and one eventual PR. Validate annotated `v0.2.0` and its peeled commit, run the provider consumer fixture in version mode, move all three manifests/guards/active authorities/current projections to exact `0.2.0`, and introduce the shared app-lifetime coordinator that owns every legacy Loki construction/`track`/`flush` call on one serial non-main executor. The protected constitution dependency-fact amendment, the narrow Owner-approved `loki02v1` repository-contract deviation record, its pointer-only `AGENTS.md` Red-lines entry, and all enumerated current-truth projections travel in this same slice; the former standalone PR03 handoff is eliminated, not deferred. Tests cover the fixed candidate from `@MainActor`: a spy proves off-main FIFO, maximum concurrency one, adjacent-only flush joining, and an intervening admission that forces a follow-up flush; an actual exact-`0.2.0` `LokiTelemetryService` with isolated storage proves its synchronous enqueue return precedes later underlying flush entry. PR01's required CI executes the regression. Endpoint/Noop/routing/log-sink behavior stays unchanged, no `maxDiskBytes` override is added, the two prior implementation verdicts remain evidence, and exact candidate `1f5f7cbf83a5aec0019910a0a3f7b9cfd05dae64` is neither published nor re-reviewed. Because dependency, governance, constitution, architecture, context, script, and workflow-comment paths are protected, PR02 retains `owner-review` and requires fresh Owner approval on the final checked head.

### PR04 / PR05 — Independent privacy repairs

PR04 removes arbitrary stringified transcription-error telemetry in VoxInfrastructure; PR05 removes localized refinement-error telemetry in VoxApplication. Each contains its own red/green sentinel regression and preserves safe Loki metrics and runtime/UI error behavior. Each depends only on merged PR00 (or an explicitly approved base containing byte-identical reviewed planning artifacts), so both may proceed in parallel with the PR01→atomic-PR02 safety chain.

### PR06 — Dormant Blob deep module

After atomic PR02, PR04, and PR05 merge, extend the existing shared coordinator with the typed Blob policy/configuration/store lifecycle, consent/identity preference state, host-eligibility policy, source plist/XcodeGen settings, and focused tests, but no production Blob call site. Missing/unexpanded source settings or default-off consent keep Blob unused and disabled. The accepted T008 coupled preference interface supplies dormant first-explicit-opt-in identity creation evidence; T009 separately makes the Application policy request provisioning only after the app supplies persisted consent plus valid interactive-host/configuration eligibility. App-lifetime reuse, live disable/re-enable with non-evicted pending-file retention, CLI/headless/test exclusion, default-capacity construction with no override, Decision 2A heartbeat boundary, Decision 1A query fixture, ordering, privacy, and disabled/invalid states are independently testable without credentials.

### PR07 — App adoption and instrumentation

The registered PR #115 remote head `bef8843f612955bba416485331f426c487e78c08`, preserved local candidates `d3c943d785e7de4c9f923891c631b367e3097a01` and `0fd6c2a4bb1ad1d640782db7e28ab18987d7e8a9`, and frozen failed Round 7 candidate `107a75ad141bf6d4d1f60bb686705ced1c5eac5e` are evidence, not execution authority. The accepted d8 behavior and five-path ownership correction remain historical baseline. Round 7 adds one bounded mechanical repair through exactly these eight paths:

1. `Packages/VoxApplication/Tests/UseCasesTests/ProductTelemetryActivationUseCaseTests.swift` (`VoxApplication` / UseCasesTests) — split the exactly-50-line startup-deferral test into named phases/helpers while retaining its assertions and the distinct false→true stale-startup winner proof;
2. `Packages/VoxPresentation/Tests/UISharedTests/MacOSSettingsViewTests.swift` (`VoxPresentation` / UISharedTests) — split the long production-parent/loading tests and independently stimulate shortcuts and provider loading in their owning panes;
3. `VoxPocket/VoxPocket/ServiceContainer.swift` (`VoxPocketApp`) — keep assembly only, extract the existing product-telemetry value construction, and split the touched initializer into private value/helper factories shorter than 50 lines;
4. `VoxPocket/VoxPocket/ProductTelemetryAssembly.swift` (new, `VoxPocketApp`) — mechanically receive the existing app-private instrumentation/notification-boundary implementation and narrow value assembly extracted from `ServiceContainer`; add no public interface, protocol, controller, state machine, worker, or executor;
5. `VoxPocket/VoxPocket/AppDelegate.swift` (`VoxPocketApp`) — mechanically split the touched launch and quick-record start/stop functions into private dependency-resolution/operation helpers shorter than 50 lines without changing lifecycle or event order;
6. `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTests.swift` (`VoxPocketApp` tests) — keep behavior tests and rewrite the resign-active proof through a launched real `AppDelegate`; split every long test into named phases/helpers and move only reusable fixtures/doubles out;
7. `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTestSupport.swift` (new, `VoxPocketApp` tests) — receive those existing fixtures/doubles, protect shared mutable state with `Synchronization.Mutex`, and justify the only remaining unchecked Combine bridges at their declarations; and
8. `VoxPocket/VoxPocket.xcodeproj/project.pbxproj` (generated `VoxPocketApp` support) — one selected untouched raw XcodeGen output, regenerated so the two new Swift files are members of the already-declared recursive app/test source sets; never hand-edit, normalize, or post-process it.

`VoxPocket/project.yml` already recursively includes `VoxPocket` and `VoxPocketTests`, so it remains byte-identical. No `Package.swift`, Infrastructure/Preferences, Presentation production source, consent-composition test, `MacOSAppScenes.swift`, coordinator, event, configuration, executor/provider, constitution, tech-context, gate, credential, release, or TestFlight path changes. The file split changes neither dependency direction nor architecture: `VoxPocketApp` still owns private assembly/platform wiring and App-boundary tests, while packages retain their existing owners. Any demonstrated ninth path or generated semantic difference outside the contract below stops implementation for a new planning decision.

#### T009 selected raw XcodeGen-output contract

- Use the existing repository entry from the `VoxPocket/` working directory: first record `xcodegen --version`, then run `xcodegen generate --spec project.yml`. Planning-host evidence observed `Version: 2.46.0`; that observation is neither a repository pin nor an implementation selector, so the implementation run records its own actual output. Do not install or upgrade XcodeGen.
- Preserve `VoxPocket/project.yml` byte-for-byte. Immediately retain/hash one raw generated `VoxPocket.xcodeproj/project.pbxproj`, make no manual edit, normalization, canonicalization, or other post-processing, and require the final tracked file to be byte-identical to that selected output. A later rerun may mint different UUIDs and must become a new selected raw output with the complete proof repeated; do not claim byte idempotency or zero generated diff.
- Compare the tracked base and selected raw project as complete parsed object/reference graphs. The only allowed additions are correct membership of `ProductTelemetryAssembly.swift` in the existing app sources/target and `BlobTelemetryInstrumentationTestSupport.swift` in the existing test sources/target. The only allowed renames are exactly two collision-free one-to-one pairs: the existing `Config.xcconfig` `PBXFileReference` UUID and its config-only `VoxPocket` `PBXGroup` UUID.
- Apply those two identifier mappings only in memory for comparison. Exhaustively traverse each declaration and every incoming/outgoing reference, including all `children` occurrences and both Debug and Release `baseConfigurationReference` values. After accounting for the two memberships and applying the two mappings, require complete structural equality: object `isa`/type, file type, name/path, `sourceTree`, children and ordering, configurations, targets, build phases, build settings, and every other project field remain unchanged.
- Do not add a canonicalizer, repository script, gate, dependency, or host configuration. A missing/colliding mapping, stale reference, extra object/field/order change, ninth implementation path, or any other generated semantic difference stops and returns exact evidence to Team Lead.

### T009 Round 7 measured structural repair

| Candidate surface | Measured Round 7 state | Required mechanical result |
|---|---|---|
| `ServiceContainer.swift` | 948 lines versus 653 on live base; touched initializer spans lines 106–267 | Extract app-private telemetry assembly into `ProductTelemetryAssembly.swift`; keep both files below 800 lines and split the initializer/value construction into functions below 50 lines |
| `AppDelegate.swift` | 490 lines; touched launch and quick-record start/stop bodies exceed the strict function limit | Keep the file below 800 lines; extract only private dependency/operation helpers so every changed/new function is below 50 lines |
| `BlobTelemetryInstrumentationTests.swift` | 789 lines; quick-record and nonblocking lifecycle tests span 72 and 65 lines before the required repair | Move fixtures/doubles to the focused support file and split phase helpers; both test files and every changed/new test/helper must remain below 800/50 lines |
| `MacOSSettingsViewTests.swift` | 437 lines; production-parent and suspended-load tests span 104 and 53 lines | Split into separately named Settings-parent, Me-parent, shortcuts-loading, provider-loading, and privacy-interactivity proofs; every test/helper below 50 lines |
| `ProductTelemetryActivationUseCaseTests.swift` | 357 lines; `startupDefersBehindExplicitTransition` spans exactly 50 lines | Split setup/release/assertion phases without changing semantics; retain all other policy assertions and keep every changed/new function below 50 lines |

The limits are strict final-tree acceptance, not estimates: every changed/new Swift file is `<800` physical lines and every changed/new function, test, closure helper, or initializer is `<50` physical lines. A final path/line-count receipt must identify every split. No assertion may be deleted merely to reduce size.

### T009 Round 7 Sendable ownership

| Test double | Required conformance/state |
|---|---|
| `QuickRecordRecordingUseCase` | `@unchecked Sendable` is allowed only with a declaration-level reason that the immutable Combine `CurrentValueSubject` bridge is not checked-Sendable; counters remain in `Mutex` |
| `QuickRecordTranscriptionUseCase` | Same declaration-level Combine-only justification; `language` and `snapshotGateActive` move into `Mutex<State>` (or equivalent typed `Mutex` values), with no naked shared mutation |
| `QuickRecordRefinementUseCase` | Same declaration-level Combine-only justification; no additional unchecked wrapper |
| `QuickRecordClipboardService` | Stateless checked `Sendable`; remove `@unchecked` |
| `RuntimeTelemetryRecorder` / `RuntimeTelemetryService` and other mutable doubles | Keep checked `Sendable` with all shared mutable state inside `Mutex`; do not hide unsafe state in a new unchecked container |

### T009 placement-correction threat model

- Existing app-shell configuration/plist and host validation remains the trust boundary; the Application policy receives only the already-validated eligibility fact and required operations, never raw configuration, a real SAS, endpoint, or credential.
- Existing consent/identity privacy boundaries remain: Preferences stores the Boolean/UUID values, the Application policy orders access, and identity is requested only after eligibility. The existing same-user local-filesystem trust model for `UserDefaults` and the app's telemetry store is unchanged.
- Moved assembly/test helpers carry only the same validated facts and operations. They add no audio, transcript, refined text, prompt, error string, arbitrary property value, external permission, dependency, transport, persistence location, or network channel.
- XcodeGen provenance inspects only `project.yml` bytes, PBX object/reference structure, hashes, and generator command/version metadata. It must not read or report real `Config.xcconfig`, `Secrets.xcconfig`, private configuration, SAS, endpoint, or credential contents. The two allowed UUID mappings are internal project-reference identity changes only and add no configuration value, target/build semantic, signing behavior, permission, storage, network, or transport channel; synthetic Release/plist, App compile/XCTest, and required CI remain separate mandatory evidence.

### T009 Round 7 old-to-new executable coverage

| Existing proof / Round 7 gap | Owning executable proof after repair | Required preserved stimulus/assertions |
|---|---|---|
| Delayed opt-in superseded by opt-out and all readiness/identity rules | Existing Application package tests through internal deterministic gates | Preserve ordered writes, waiter completion, zero losing-intent identity/activation, startup deferral, stale-activation rejection, disable/re-enable UUID reuse, retry, and readiness assertions |
| False→true startup overlap winner | `ProductTelemetryActivationUseCaseTests.staleStartupCannotChangeFalseThenTrueWinnerSnapshot` | Preserve `[false, true]`, one reused identity, readiness/winner snapshot before stale-startup release, and no post-release change; structural splitting must not weaken it |
| Every Settings choice forwards while only latest renders | Existing Presentation view-model test | Preserve the public `onConsentChanged` closure contract used by the real App consumer |
| Consent-only persistence and identity provisioning stay separated | Existing Infrastructure preferences tests | Preserve zero identity from Boolean-only persistence and no consent rewrite during provisioning; internal gates stay package-test-only |
| Shortcuts loading/default suppression | Split mounted `.shortcuts` executable UI test | Suspend only `loadShortcuts`, wait until that exact gate enters, assert loading, reject shortcut defaults including `F7`/`Fn`, then release |
| Provider/text loading/default suppression was not stimulated | New split mounted `.text` executable UI test in the same Presentation test path | Suspend only `loadProviderSettings`, wait until that exact gate enters, assert loading, reject temporary provider/text defaults including `Azure`, then release; retain independent privacy-pane interactivity while loading is suspended |
| Rapid release plus startup/recording/session/resign-active production boundaries | Split App XCTest using actual `AppDelegate` / `ServiceContainer` callers | Preserve start→stop rapid release, exact event/property/launch-duration/identity assertions, nonblocking lifecycle behavior, one-generation construction, disable/re-enable, and flush counts; direct instrumentation remains supplemental |
| Same-turn FIFO resign-active test constructed but never launched its delegate | Repaired App XCTest through the real lifecycle | Create the default-off fixture/container/model/delegate; call `applicationDidFinishLaunching`; await `waitForPendingStartup()` and container startup completion; assert zero identity/construction/event before opt-in; opt in through the real Settings model and await consent completion; invoke real `applicationWillResignActive`; wait until the first FIFO flush gate enters; record later `.settingsOpened` while suspended; release and await resign completion; invoke/await a second real resign-active flush; assert exactly `construct → flush → track product.user_action → flush` |
| Missing/invalid configuration and excluded hosts | Existing unchanged consent-composition tests | Preserve consent persistence with zero identity/bootstrap/store/enqueue/network work |

There is no authorized assertion deletion, skip, relaxation, source-inspection substitution, or second state machine. The repair changes only mechanical placement/synchronization and the completeness of executable stimuli.

### T009 evidence classes

- **Source parse (supplemental only)**: a direct Swift parse can catch syntax/conditional-compilation errors but cannot typecheck ordinary-import access, project membership, actor isolation, or execute tests.
- **VoxApplication SwiftPM build/test**: executes internal DEBUG policy/race/cancellation seams, including the false→true stale-startup proof. It does not prove the App consumer.
- **VoxPresentation SwiftPM build/test**: executes mounted shortcuts/provider loading and default-suppression behavior. Infrastructure SwiftPM tests separately retain the consent/identity storage proof.
- **Raw XcodeGen provenance**: record the existing generation command and actual installed version, prove `project.yml` byte identity, bind the final tracked project to the selected untouched raw-output hash/bytes, and complete the two-membership/two-UUID-bijection whole-project proof above. This proof neither assumes UUID stability nor substitutes for compilation.
- **App consumer compile**: after the raw-output proof, the App target must compile ordinary imports and both new files. Package success or project-structure equivalence cannot substitute for this boundary.
- **App XCTest execution**: the selected `VoxPocketTests` must execute/pass through real `AppDelegate` / `ServiceContainer` callers, including rapid release and the complete resign-active FIFO sequence. `Testing cancelled because the build failed` supplies no XCTest evidence.
- **Required CI**: evidence binds the exact candidate head; independent `App target` and review requirements must pass. An aggregate success cannot replace a failed or missing App-target compile/XCTest result.

### PR08 — Synthetic Release CI

Add only the unsigned synthetic Release processed-plist helper, tests, and required CI wiring. Fake non-routable values are used; signing, upload, TestFlight, real secrets, and network senders are excluded.

### PR09 — TestFlight secure injection

Add only the authorized macOS TestFlight temp-`0600`-xcconfig path across workflow/Fastlane/tests/docs. Preserve the manual trigger, signing, numbering, upload, tag behavior, and iOS disablement. This PR alone carries the exact Decision 1A Owner commands and both secret-add commands.

### Production — Owner-controlled evidence

After every extant implementation PR (PR01, PR02, and PR04–PR09) merges, Owner policy/secret provisioning and fresh Owner release authorization allow the existing manual workflow to produce one macOS TestFlight build. The tester separately enables “Send usage data” in Settings and performs one approved action; release authorization is not consent. Team Lead records only the build number, run/revision, blob name, and terminal category from read-only evidence.

## Acceptance Traceability

| Acceptance / requirement | Slice | Tasks | Evidence |
|---|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC6; FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-010, FR-011, FR-012, FR-015, FR-021 | PR06/PR07 | T008, T009 | typed contract; default-capacity initializer/heartbeat fixture; shared-coordinator ordering/join/retry; startup/action/flush adoption; preservation of atomic PR02's legacy seam |
| US1/AC5; FR-020; SC-006 | Production | T012 | explicit Owner authorization plus separate tester Settings opt-in; one approved action; exact merged/run revision; TestFlight build number; read-only blob name; no payload/credential evidence |
| US2/AC1; FR-005–FR-008, FR-015 | PR04–PR07 | T006–T009 | whole-event rejection plus Infrastructure/Application/app-shell privacy sentinels |
| US2/AC2; FR-008, FR-009; RB-001 | PR04/PR05 | T006, T007 | red/green localized/stringified-error tests and closed/omitted replacement fields |
| US2/AC3, US2/AC4; FR-010, FR-011 | PR06 | T008 | missing/empty/unexpanded zero-state and present-invalid fixed-diagnostic fixtures |
| US2/AC5; FR-014, FR-015, FR-016, FR-018, FR-019 | PR06/PR08/PR09 | T008, T010, T011 | SAS fixture; synthetic Release; temp-xcconfig/raw+escaped log absence; preserved gates |
| US3/AC1; FR-001 | atomic PR02 | T002–T004, T013 | provider version-mode consumer check; exact `0.2.0`; matching manifests, guards, authorities, and projections; annotated-tag integrity evidence only |
| US3/AC6; FR-025; RB-004 | PR01/atomic PR02 | T001, T005 | required app-test gate; off-main provider construction/`track`/`flush` spy; adjacent-only coalescing and intervening-admission follow-up; actual-adapter enqueue-return-before-flush proof; zero raw-provider bypass |
| US3/AC7; FR-026; RB-005 | atomic PR02/PR06/PR07 | T002–T005, T008, T009, T013 | legacy and Blob default-capacity construction/adoption; zero `maxDiskBytes` override; accepted eviction, loss-accounting, and rollback notes |
| SC-008 | PR01/atomic PR02/PR06/PR07 | T001, T005, T008, T009, T013 | required main-actor-originating off-main/FIFO regression, actual exact-`0.2.0` adapter barrier fixture, and structural zero-bypass/zero-override inspection across legacy and Blob paths |
| US3/AC2; FR-002, FR-003, FR-008, FR-009, FR-025 | atomic PR02/PR04/PR05/PR07 | T002–T007, T009, T013 | preserved endpoint/Noop/routing/log-sink semantics; shared legacy executor; privacy-only removals; no Blob fan-out |
| US3/AC3; FR-013, FR-015, FR-016 | PR06/PR08 | T008, T010 | XcodeGen/plist contract and processed synthetic Release app |
| FR-017 | PR06–PR09 | T008–T011 | source settings, adoption, processed Release proof, and TestFlight path stay aligned |
| US3/AC4; FR-014, FR-015, FR-016, FR-018 | PR09 | T011 | path-only `-xcconfig`; mode/cleanup; raw+escaped absence; unchanged release invariants |
| US3/AC5; FR-018, FR-019; SC-005 | PR00–PR09 | T000–T011, T013 | per-PR one-goal/exact-head evidence and applicable Owner gates; exact commands only in PR09 |
| US1/AC7, US1/AC8, US2/AC6; FR-022–FR-024; SC-007 | PR06/PR07 | T008, T009 | isolated `UserDefaults` consent/identity fixtures; Application policy-interface tests for persist-before-provision, eligibility, overlapping intents, startup deferral, stale-result rejection and readiness; consent-only persistence with zero identity under missing/invalid configuration; eligible interactive-app provisioning/reuse; preserved macOS/cross-platform Settings consent-toggle tests; disable→off no-host-deletion/non-evicted-file plus UUID retention→later-opt-in and eligible-launch reuse of the same app-lifetime UUID; no v1 Reset/rotation surface; excluded-host zero-construction fixtures |
| SC-001 | PR04–PR07 | T006–T009 | all supplied prohibited sentinels rejected before persistence/transport |
| SC-002 | PR06 | T008 | zero identity-provider/store/enqueue/network calls for disabled Debug/Release fixtures |
| SC-003 | PR08/PR09 | T010, T011 | expanded synthetic plist plus zero raw/escaped sentinels or value-bearing arguments/logs |
| SC-004 | PR01, PR02, PR04–PR09 | T001–T011, T013 | each extant PR's focused verification, `scripts/verify`, exact-tree review, and no weakened test |

Every stable acceptance criterion and functional requirement maps to an owned task and evidence surface. RB-001 is the approved arbitrary-error removal; RB-002 preserves separation by forbidding legacy Loki fan-out; RB-003 preserves host-controlled queue files and every other transport, metric, guard, test, signing/upload step, and platform restriction; RB-004/RB-005 are the explicit Lead-approved legacy execution and bounded-retention changes. Production-only acceptance remains explicitly external rather than being claimed by repository tests.

## Verification Strategy

[`quickstart.md`](./quickstart.md) is the executable verification contract. Required implementation evidence:

1. After PR00, PR01 adds only required App-target CI that regenerates the Xcode project and executes `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -destination 'platform=macOS' -only-testing:VoxPocketTests test` with signing disabled; the existing suite passes before any runtime or pin change;
2. Atomic PR02 validates annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peeling to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, runs `external_consumer.py --version 0.2.0`, updates the full current-truth path list with every T002–T004/T013 projection, records the narrow Owner-approved `loki02v1` repository-contract deviation in the protected constitution with only its pointer under `AGENTS.md` Red lines, proves old selectors absent and no consumer `maxDiskBytes` override, and in that same final tree uses a main-actor-originating spy to prove legacy provider construction, `track A`, `track B`, and flushes execute FIFO with maximum underlying concurrency one and `Thread.isMainThread == false`;
3. Atomic PR02 separately proves adjacent flushes join while `flush → track B → flush` performs B and a serialized follow-up underlying flush before the later waiter resumes. An actual exact-`0.2.0` `LokiTelemetryService` with isolated temporary storage sits behind a test-only boundary recorder and proves the real adapter's `track` completion precedes later underlying `flush` entry. This evidence relies on pinned `0.2.0`'s synchronous `TelemetryQueue.enqueue` contract and may not be replaced by a synchronous fake, sleep, yield, or double flush. Structural evidence proves no raw-provider bypass, and PR01's required CI executes all regressions;
4. Independently after PR00 and in parallel with the PR01→atomic-PR02 chain, PR04 and PR05 each demonstrate their privacy test red against the unsafe baseline, then green without assertion weakening, and pass their own package layer plus `scripts/verify`;
5. Only after atomic PR02, PR04, and PR05 merge, PR06 proves the representative stored-policy query accepted and `sp=cw`/user-delegation/unknown-name forms rejected; it extends the reviewed coordinator and tests provider-default Blob construction with no `maxDiskBytes` argument, SDK heartbeat exemption, coordinator-only host construction/`track`/`flush`, privacy allowlists, disabled/invalid config, default-off consent, the accepted T008 coupled-interface first-explicit-opt-in UUID evidence, disable→off no-host-deletion/non-evicted-file plus UUID retention, later-opt-in and eligible-launch reuse of the same app-lifetime UUID, no v1 install-ID Reset/rotation surface, excluded-host policy, ordering, joined flush, and non-evicted retryability;
6. PR07 retains its macOS/cross-platform Settings UI wiring and consent-only preference interface with unchanged T008 provisioning behavior. The accepted d8 placement/test-boundary correction remains binding, and the Round 7 eight-path mechanical repair adds checked/Mutex-owned test state, strict `<800`/`<50` receipts, independently gated shortcuts/provider loading regressions, and the complete launched-`AppDelegate` resign-active FIFO sequence. Package policy/UI tests, generated-project App consumer compilation, and real App XCTest remain distinct evidence classes; direct instrumentation and source parse cannot substitute. Missing/invalid configuration or excluded hosts remain at zero identity/construction, and atomic PR02's off-main FIFO/join/retry/default-capacity behavior remains unchanged;
7. PR08 uses the repository generation entry from `VoxPocket/project.yml`, records raw-output provenance under R-014 when generation occurs, and inspects an unsigned synthetic Release app's processed plist; generation/build/plist success does not prove UUID stability or idempotency;
8. PR09 proves the xcconfig is runner-temp/untracked/`0600`, only its path reaches `-xcconfig`, cleanup runs on every terminal path, both raw and escaped sentinels are absent from captured Release logs, and existing manual release invariants remain;
9. every implementation PR passes its focused commands, `scripts/verify`, `git diff --check`, and required CI; PRs forcing full selection also run `scripts/verify --all` locally when practical and rely on the required full CI lanes at the exact head;
10. every PR freezes its own candidate for independent content review before publication, publishes only that tree, and proves equality of local SHA, remote branch OID, and PR `headRefOid`; evidence is never reused across PRs;
11. stacked branches declare their parent; after a prerequisite squash-merges, the child is retargeted/rebased onto `origin/main`, then fully reverified and rereviewed because its SHA changed;
12. production proof occurs only after every extant implementation PR (PR01, PR02, and PR04–PR09) merges, Owner provisioning, a new explicit Owner authorization, and a separate tester opt-in through “Send usage data”; authorization never substitutes for consent.

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
├── Sources/UseCases/
│   ├── DefaultRefinementUseCase.swift
│   └── ProductTelemetryActivationUseCase.swift
└── Tests/UseCasesTests/ProductTelemetryActivationUseCaseTests.swift

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

**Structure decision**: PR01 adds only required app-test CI. Atomic PR02 combines the minimal VoxPocketApp coordinator seam with all T002–T004/T013 exact-version/current-truth work because only exact `0.2.0` exposes the synchronous enqueue-return boundary that makes the flush contract achievable; there is no publishable old-`0.1.0` intermediate and no standalone PR03. PR04/PR05 own privacy behavior separately and may proceed after PR00 in parallel with that ordered chain. PR06 waits for atomic PR02 plus PR04/PR05 and extends the existing coordinator into the dormant consent-capable Blob deep module plus Infrastructure preference state. PR07 remains one vertical adoption goal: accepted d8 makes package-internal test seams truly internal, and the bounded Round 7 eight-path repair mechanically splits oversized app/test surfaces while preserving package policy ownership and real App integration proof. The new assembly/support files add no public abstraction or dependency; recursive `project.yml` sources stay unchanged, and the tracked project is one selected untouched raw generator output whose only permitted semantic changes are two memberships plus the two exhaustively mapped existing UUID renames. PR07 reuses the existing coordinator and adds no controller, state machine, manager, worker, protocol layer, or executor. Root support splits synthetic CI (PR08) from TestFlight secret governance (PR09). Generated Xcode project files are outputs, never hand-edited, normalized, or post-processed sources.

## Constitution Check — After Design

PASS with no constitutional exception. PR01 remains the separate required-CI gate. Lead decision `loki02v1` deliberately makes PR02 one atomic dependency/runtime migration because the required barrier cannot exist on `0.1.0`; exact `0.2.0` synchronous enqueue completion and the coordinator are reviewed/tested in the same final tree. The legacy provider is constructed and invoked only on one dedicated serial non-main executor, and main-actor-originating spy plus actual-adapter-shaped regressions prove the boundary in required CI without sleep/yield/double-flush. The design preserves package direction, makes every underlying legacy/Blob construction/`track`/`flush` structurally non-main, defaults consent off in Preferences, centralizes consent/identity/activation ordering in the Application use case, excludes non-interactive or invalidly configured hosts before identity/Blob construction, narrowly records Decision 2A for SDK-owned heartbeat, rejects private/free-form data before accepted state, uses synthetic credential-free CI, keeps XcodeGen authoritative, isolates Blob files from Loki, and separates Owner-controlled release evidence from implementation authority. The authorized execution-timing, default-capacity/eviction/rollback, and arbitrary-error changes are explicit and test/document-covered; every other legacy/release behavior remains a preservation surface.

## Dependencies and External Gates

- Repository base: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`.
- Repo contract: shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`.
- Provider dependency: shared-telemetry exact `0.2.0`; annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peels to reviewed commit `903f4b9bc01cfcfeba3ce96e13519d841781b40a`. Those OIDs are integrity evidence, not revision selectors.
- Planning gate: AI Reviewer exact-revision PASS before Team Lead implementation dispatch.
- Per-PR candidate gate: AI Reviewer exact frozen-tree PASS plus explicit publication permission before each commit/push/PR; a changed or rebased SHA is reviewed again.
- Important-path gate: applicable Owner approval and required checks on each exact non-Draft PR head.
- Production gate: every extant implementation PR (PR01, PR02, PR04–PR09) merged; Owner-created create-only stored policy/container service SAS; both GitHub secrets; a new explicit Owner authorization before manual TestFlight dispatch; then a separate tester Settings opt-in before the approved action used for evidence.

## Risks and Escalation Conditions

| Risk | Mitigation / escalation |
|---|---|
| `v0.2.0` is missing, moved, not annotated, or peels to a commit other than `903f4b9bc01cfcfeba3ce96e13519d841781b40a` | Block atomic PR02 and escalate the exact tag evidence. Do not fall back to a branch or revision selector; ordinary later movement of provider `main` is irrelevant. |
| SDK API differs from reviewed docs | Stop and return exact compiler/provider-contract evidence; do not invent an adapter wrapper or widen shared-telemetry scope. |
| Stored-policy SAS query differs | Compare the synthetic query-name fixture against the pinned validator. Reject user-delegation keys or `sp=cw`; do not broaden the provider or generate a real token. |
| Synchronous provider I/O leaks onto `@MainActor`, or flush outruns a real enqueue | Dedicated serial non-main executor plus a main-actor-originating spy covering construction, FIFO, adjacent-only coalescing, intervening-admission follow-up, and `Thread.isMainThread == false`; a separate exact-`0.2.0` actual-adapter-shaped regression records real `track` return before later `flush` entry. Structural assertions reject raw-provider bypass. A generic actor-isolation claim, immediately returning synchronous fake, sleep/yield, or double flush is insufficient. SDK heartbeat remains only the Decision 2A exemption. |
| Consent, identity ordering, or host exclusion is bypassed | `DefaultProductTelemetryActivationUseCase` is the sole policy owner: the accepted `ProductTelemetryPreferences.persistConsent(_:)` adapter writes only the Boolean, and unchanged T008 provisioning adapters are invoked only after the app supplies eligible interactive-host plus valid-configuration facts. Application package regressions cover overlapping transitions, startup deferral, waiter termination, ordered writes, eligibility-before-identity, stale activation rejection, and readiness gating; real `AppDelegate` / `ServiceContainer` boundary regressions block eager identity/service creation, off-state admission/upload, implicit resume, host/manual pending-file deletion, or CLI/headless/test construction. Provider-owned eviction under the accepted capacity policy is not a bypass. |
| Package-internal test hooks leak into the App consumer or App tests duplicate Package race policy | Keep activation checkpoints/awaiters and the Preferences write gate internal to their owning package tests; remove the redundant UIShared notification-center overload; use the existing public Settings callback plus the app-owned defaulted notification-center assembly input for real-container proof. Require Package tests and App consumer compile/XCTest as distinct evidence, and reject source parse as a substitute. |
| Test doubles race or hide mutable state behind unchecked conformance | Require checked `Sendable` plus `Mutex` for mutable/stateless doubles. Allow unchecked conformance only on the three immutable Combine-subject bridges with declaration-level justification; no unchecked wrapper or naked mutable language/gate state. |
| Mechanical splitting weakens UI/lifecycle behavior or misses project membership | Require the exact old-to-new assertion map, strict final line receipts, independently entered shortcuts/provider gates, the launched real-`AppDelegate` two-flush order, selected raw XcodeGen output with the full two-membership/two-bijection proof, App consumer compile, and executed App XCTest. Any assertion deletion, ninth path, extra generated semantic difference, cancelled build, or aggregate-only result stops delivery. |
| Privacy policy requires arbitrary strings | Reject the event or add a new Owner-approved closed label. Never sanitize/redact after persistence. |
| Store lease/capacity/rollback behavior is incompatible | Keep the 50 MiB provider default and loss ledger; stop producers, finish pending eviction cleanup with the capacity-aware `0.2.0` reader after storage is writable, and never overlap old/new writers. Already evicted events are unrecoverable. Return exact adapter evidence rather than adding an override or manually reusing/deleting persisted state. |
| XcodeGen produces unexpected output | Record the actual command/version and selected raw-output hash, then prove final byte equality and the complete two-membership/two-bijection equivalence. A rerun may mint new UUIDs but requires a fresh full proof; any other difference stops. Never normalize, patch, canonicalize, or hand-edit the generated project, install/upgrade the generator, or absorb unrelated output. |
| Synthetic Release proof needs signing/network | Treat as a design failure and return to the app/root-support owner; do not introduce secrets or live access. |
| Secret or sentinel value appears in logs/arguments/tests/diff | Stop publication, rotate if real, remove the exposure through the owning release seam, and rerun raw-plus-escaped absence evidence. Masking alone is not acceptance. |
| Important approval/check is missing | Keep the PR unmerged in Owner review; never bypass CODEOWNERS/ruleset protection. |
| Owner has not provisioned/authorized production, or tester consent is absent | Repository delivery may complete, but T012 remains blocked; no workflow is dispatched without Owner authority and no telemetry action/blob evidence is attempted without separate tester opt-in. |

## Complexity Tracking

No constitutional violation is requested. Atomic PR02's constitution amendment changes the selected immutable dependency fact, not a red line, and records rule/reason/migration impact with matching projections. Combining that protected current-truth work with the coordinator is the Owner-selected remedy for an otherwise impossible intermediate contract; PR01 CI governance remains separate, atomic PR02 retains `owner-review`, and fresh Owner approval is required on its final checked head. The shared coordinator/executor is required by the provider's synchronous construction/persistence boundary and deepens the app interface: legacy callers retain the existing `TelemetryService` surface while all provider work is serialized off-main; later Blob callers submit two typed event variants and lifecycle commands without knowing configuration, identity, store, capacity policy, transport, or SDK heartbeat details. The accepted consent-only Infrastructure seam remains value storage. `ProductTelemetryActivationUseCase` is the single deeper Application interface that concentrates persistence ordering, eligibility-before-identity, activation generation, and readiness while App adapters hide Blob/configuration details; it changes no dependency edge and introduces no second state machine or executor.
