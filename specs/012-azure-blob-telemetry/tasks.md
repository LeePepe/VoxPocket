---

description: "Single-goal PR graph with layer-scoped tasks for privacy-safe Azure Blob product telemetry"

---

# Tasks: Privacy-safe Azure Blob product telemetry

**Input**: Design documents from `specs/012-azure-blob-telemetry/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/product-telemetry-contract.md`, `quickstart.md`, `checklists/requirements.md`

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**Organization**: PR00 lands the exact reviewed plan. PR01 adds only the required App-target test gate. Atomic PR02 combines T005 with all T002–T004/T013 work so the exact `0.2.0` synchronous enqueue boundary and serialized non-main coordinator exist in one final checked tree; there is no standalone PR03 or publishable old-`0.1.0` intermediate. PR04 and PR05 are independent privacy repairs that may run in parallel after PR00; PR06 waits for atomic PR02 plus PR04/PR05 and extends that coordinator for Blob consent rather than adding another executor. PR07–PR09 retain separate adoption, synthetic-CI, and TestFlight-governance goals. MY-1836 / PR #115 preserves remote `bef8843f612955bba416485331f426c487e78c08`, local evidence `d3c943d785e7de4c9f923891c631b367e3097a01` / `0fd6c2a4bb1ad1d640782db7e28ab18987d7e8a9`, frozen product head `02e5e76532deaf21600b88b7318ad3c60034314d`, and all Round 1–8/CI history without treating them as execution authority. Reviewed revision `48967aa75b8cdd7e5224f5bd69797b6a6f247510` / manifest `dff64160aebf008d7bce0c12f40ba60ffe7b7ab5e0a19ce6d81e48e5b380633f` is merged byte-identically through live base `cba86dbeb69152f1a6e8628bde95cf12c92ee864`. T009 preserves the accepted d8 ownership and the historical Round 7 eight-path mechanical/XcodeGen subset, then adds only the two existing VoxPresentation model/test paths required for committed-state peer convergence. The new pair reuses the existing notification/completion and preference-read seams, changes no project membership, and leaves every product/privacy/lifecycle contract intact. An independent planning PASS and separate Team Lead execution permission are required before any product mutation, Round 9, review, push, or CI rerun. Every PR otherwise freezes, verifies, receives independent exact-tree review/publication permission, publishes only that tree, proves local/remote/PR-head equality, passes required CI, and obtains applicable CODEOWNERS/Owner approval. Evidence never transfers to another or rebased head.

## Per-PR delivery contract

Every PR task below includes this acceptance in addition to its task-local checks:

1. Declare the base and start the PR `Intent` with its one-sentence observable goal.
2. Run focused checks plus `scripts/verify` and `git diff --check` at the frozen candidate; run `scripts/verify --all` for forced-full-selection changes when practical and require all server checks on the exact head.
3. Obtain independent AI Reviewer spec/architecture `PASS` and explicit publication permission for that exact tree.
4. Publish only the reviewed tree, then prove `git rev-parse HEAD`, the remote branch OID, and PR `headRefOid` are byte-identical.
5. Complete every PR-template section, preserve RB-001–RB-005, and wait for applicable CODEOWNERS/Owner approval and required checks.
6. If stacked, declare the parent. After a prerequisite squash-merges, retarget/rebase the child onto `origin/main`, rerun all verification, and obtain a new exact-revision review because the SHA changed.

## Phase 0: PR00 — Reviewed planning package

**Goal sentence**: After this PR, VoxPocket `main` contains the exact independently approved MY-1818 planning contract and no implementation change.

- [ ] T000 [US3] Publish only the exact AI-Reviewer-PASS planning artifacts in `specs/012-azure-blob-telemetry/**`, `.specify/feature.json`, and the managed Spec Kit block in `CLAUDE.md`

### T000 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `_root support` planning; context `docs/architecture/tech-context.md` |
| PR / vertical slice | PR00 / planning prerequisite for US1–US3 |
| Files in scope | `specs/012-azure-blob-telemetry/**`; `.specify/feature.json`; only the managed `<!-- SPECKIT START -->`…`<!-- SPECKIT END -->` block in `CLAUDE.md` |
| Files out of scope | Constitution/architecture/dependency truth; package/app source; manifests; workflows; Fastlane; scripts; implementation; Azure/GitHub mutation |
| Interface impact | Planning only; no runtime/build/release behavior |
| Task-local acceptance | Publish the exact planning revision that passed the spec gate. Blob IDs for all eight artifacts match the verdict. No implementation file or unreviewed planning edit is included. `CLAUDE.md` remains a thin AGENTS pointer plus managed block. |
| Verification | Spec Kit prerequisites; cross-artifact Analyze; requirements checklist; `scripts/verify --policy`; `git diff --check`; exact planning commit/remote/PR OID; Owner approval because `CLAUDE.md` is CODEOWNERS-protected |
| Blocking edges | No implementation PR starts from an unreviewed/unpublished plan. PR01, PR04, and PR05 each depend on merged PR00, or on an explicitly approved base containing byte-identical reviewed artifacts. Atomic PR02 depends on PR01; no standalone PR03 remains. |

## Phase 1: Ordered PR01 → atomic PR02 safety chain

### PR01 — Required app-unit-test CI gate

**Goal sentence**: After this PR, required CI executes the existing macOS `VoxPocketTests` target, with no product, dependency, or runtime change.

**Independent test**: the workflow regenerates the project and runs the current macOS App-target tests with signing disabled; existing required checks and local repository gates still pass.

- [ ] T001 [US3] Add the required macOS App-target unit-test invocation in `.github/workflows/ci.yml`

| Field | Contract |
|---|---|
| Owner / context | `_root support`; `docs/architecture/tech-context.md` |
| In scope | `.github/workflows/ci.yml` only; required CI execution of the already-existing `VoxPocketTests` target |
| Out of scope | Product/package/app source and tests; manifests, dependency selectors, AGENTS, constitution, architecture/current-truth docs, Fastlane/TestFlight, secrets, Blob behavior |
| Acceptance / verification | After the existing XcodeGen step, invoke `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -destination 'platform=macOS' -only-testing:VoxPocketTests test` with signing disabled. Prove the current suite passes, workflow syntax remains valid, no existing required lane is weakened, and `scripts/verify --policy` plus `scripts/verify` pass. |
| Edges / gate | Depends only on PR00. Blocks PR02 so the new coordinator regression is mechanically executed when introduced. Owner approval is required for `.github/**`. |

### PR02 — Atomic exact 0.2.0 / off-main legacy migration

**Goal sentence**: After this PR, every VoxPocket consumer, guard, and current authority resolves shared-telemetry exact `0.2.0`, and every legacy Loki provider construction/`track`/`flush` operation executes in admission order on one serialized non-main coordinator whose real enqueue completion is a flush-barrier input.

**Independent test**: annotated `v0.2.0` peels to the reviewed commit; the provider version-mode consumer fixture and all three package suites pass; the enumerated active truth/projection set contains exact `0.2.0` with no revision selector or `maxDiskBytes` override; a main-actor-originating spy proves off-main FIFO, maximum concurrency one, adjacent-only flush joining, and the required follow-up flush after an intervening track; and an actual exact-`0.2.0` `LokiTelemetryService` with an isolated temporary store behind a test-only boundary recorder proves its synchronous `track` return occurs before later underlying `flush` entry. The actual-adapter barrier proof uses no sleep, yield, double flush, second scheduler, or synchronous-fake-only substitute.

- [ ] T005 [US3] Add the shared serialized non-main legacy telemetry seam and tests in `VoxPocket/VoxPocket/TelemetryLifecycleCoordinator.swift`, `VoxPocket/VoxPocket/ServiceContainer.swift`, `VoxPocket/VoxPocketTests/TelemetryLifecycleCoordinatorTests.swift`, `VoxPocket/VoxPocket.xcodeproj/project.pbxproj` only if regenerated output changes, and update its runtime/concurrency projection in `VoxPocket/tech-context.md`
- [ ] T013 [US3] Update root dependency guards, the protected one-time policy-deviation record/pointer, and current-truth projections in `AGENTS.md`, `README.md`, `.specify/memory/constitution.md`, `docs/architecture/tech-context.md`, `docs/architecture/packages-architecture.md`, `scripts/ci/fetch-external-deps.sh`, `scripts/tests/test_app_logging.py`, `docker/telemetry/README.md`, and the dependency-only comment in `.github/workflows/testflight.yml`
- [ ] T002 [US3] Update the VoxInfrastructure manifest/projections in `Packages/VoxInfrastructure/Package.swift`, `Packages/VoxInfrastructure/tech-context.md`, `Packages/VoxInfrastructure/OVERVIEW.md`, and `Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/README.md`
- [ ] T003 [US3] Update the VoxApplication dependency in `Packages/VoxApplication/Package.swift`
- [ ] T004 [US3] Update the VoxPresentation dependency in `Packages/VoxPresentation/Package.swift`

#### Atomic PR02 task metadata

| Task | Owner / context | In scope and interface | Out of scope | Task-local acceptance and verification | Edges |
|---|---|---|---|---|---|
| T005 | `VoxPocketApp`; `VoxPocket/tech-context.md` | Internal `TelemetryService` facade/coordinator, lazy raw-provider factory, `ServiceContainer` injection, coordinator regression, generated Xcode project output, and current runtime/concurrency projection | T013/T002–T004-owned dependency/guard/governance paths; event vocabulary/properties; endpoint/token/Noop selection; Loki log sink; package caller source; Blob service/consent/configuration; source project/plist settings; real identifiers/credentials | Tests precede adaptation. The coordinator uses one dedicated serial non-main executor, lazily constructs the exact-`0.2.0` legacy provider there, and is the only underlying caller of legacy `track`/`flush`; existing callers receive only its facade. From `@MainActor`, the scheduling spy proves construction/operations off-main, FIFO, maximum concurrency one, adjacent flush joining, and `flush → track B → flush` ordering where B completes and a follow-up underlying flush finishes before the later waiter resumes. A deterministic actual-adapter-shaped fixture places an exact-`0.2.0` `LokiTelemetryService` with isolated temporary storage behind a test-only boundary recorder and proves `actual track returned` before `underlying flush entered`; this is the barrier proof because pinned `0.2.0` synchronously completes `TelemetryQueue.enqueue`'s atomic write attempt or retained-memory fallback before returning. A synchronous fake alone is insufficient. Preserve every existing test, endpoint/Noop selection, and the Loki log sink. If generation occurs, retain one untouched raw output, record the actual command/version, and compare its task-local expected generated delta completely; never assume a repository-pinned or idempotent generator. Run app-python, `scripts/verify --layer VoxPocketApp`, and `scripts/verify`; use only the repository-documented route for app tests. | Depends on merged PR01 and is atomic with T013/T002–T004. No task row is a separately publishable intermediate. Blocks PR06. |
| T013 | `_root support`; `docs/architecture/tech-context.md` | Root guard/current truth, provider-default migration/rollback documentation, structural assertions, deliberate constitution dependency-fact amendment plus one-time repository-contract deviation record, and pointer-only `AGENTS.md` Red-lines update; no new public runtime API | T005-owned app runtime/test adaptation; package privacy adaptation; Blob runtime/synthetic Release CI; required-CI wiring; Fastlane behavior; real identifiers/credentials; shared-telemetry edits | Require SwiftPM `exact: "0.2.0"`; verify annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peels to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, record both OIDs as integrity evidence only, forbid branch/revision selectors or fallback, and run provider `external_consumer.py --version 0.2.0`. The existing CODEOWNERS-protected constitution states the dependency rule/reason/migration and records the Owner-approved `loki02v1` one-time deviation from repository-contract change-kind separation; `AGENTS.md` Red lines replaces “Approved exceptions: none” with only a pointer to that record, and neither text authorizes any broader exception or weakens a red line. Document accepted pinned `ai/MIGRATION.md`: no `maxDiskBytes` override, 50 MiB default, whole-oldest-batch eviction, oversized-event rejection, durable loss accounting, cleanup-before-rollback, and irrecoverable evictions. Prove raw `LokiTelemetryService` construction exists only behind T005's seam and no production consumer passes `maxDiskBytes:`. Run focused root tests, `scripts/verify --policy`, and `scripts/verify`; scope old-selection searches to current truth and preserve historical evidence. | Atomic with T005/T002–T004 in PR02; dependency/current-truth, policy-deviation record/pointer, and runtime assertions are reviewed on one final tree. |
| T002 | `VoxInfrastructure`; `Packages/VoxInfrastructure/tech-context.md` | Manifest and current Infrastructure dependency projections only | All Infrastructure source/privacy tests/behavior | Exact selection equals T013; `swift build && swift test` from `Packages/VoxInfrastructure`; `scripts/verify --layer VoxInfrastructure`; no source/test diff | Dependency-order-independent inside the atomic candidate; same sole writer and final head as T005/T013/T003/T004. |
| T003 | `VoxApplication`; `Packages/VoxApplication/tech-context.md` | Manifest only | Application source/privacy tests/behavior | Exact selection equals T013; `swift build && swift test` from `Packages/VoxApplication`; `scripts/verify --layer VoxApplication`; no source/test diff | Dependency-order-independent inside the atomic candidate; same sole writer and final head as siblings. |
| T004 | `VoxPresentation`; `Packages/VoxPresentation/tech-context.md` | Manifest only | Presentation source/tests/UI behavior | Exact selection equals T013; `swift build && swift test` from `Packages/VoxPresentation`; `scripts/verify --layer VoxPresentation`; no source/test diff | Dependency-order-independent inside the atomic candidate; same sole writer and final head as siblings. |

**Atomic PR02 publication**: one original Fullstack writer owns the combined fixed tree after fresh planning `PASS` and Team Lead execution approval. Preserve both earlier implementation verdicts and candidate `1f5f7cbf83a5aec0019910a0a3f7b9cfd05dae64`; do not publish or re-review that superseded candidate. The final combined PR is important/Owner-gated due constitution, AGENTS, architecture, contexts, manifests, `scripts/ci/**`, and `.github/**`; its protected policy record/pointer make the one-time `loki02v1` repository-contract deviation auditable, retain `owner-review`, and require fresh Owner approval on the final checked head. The former MY-1832/standalone PR03 route remains parked/blocked history with no second writer, while all T002–T004/T013 scope is preserved here.

## Phase 1b: Parallel PR04 / PR05 privacy repairs after PR00

### PR04 — VoxInfrastructure arbitrary-error privacy

**Goal sentence**: After this PR, transcription failure telemetry cannot carry arbitrary stringified error or voice/text content while safe event semantics remain.

- [ ] T006 [US2] Add a red/green privacy regression and remove/close arbitrary transcription error fields in `Packages/VoxInfrastructure/Sources/TranscriptionKit/VoxPocketTelemetryEventName.swift`, `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift`, and new `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitTelemetryPrivacyTests.swift`

| Field | Contract |
|---|---|
| Owner / context | `VoxInfrastructure`; `Packages/VoxInfrastructure/tech-context.md` |
| Out of scope | Manifest/context/dependency selection; Blob/app/Application/Presentation/root changes; Loki endpoint/store; UI/domain error behavior; shared-telemetry |
| Interface impact | Existing telemetry name and safe duration/count/outcome semantics remain; arbitrary `reason` becomes a closed content-free category or is omitted |
| Acceptance / verification | Demonstrate sentinel test red before the source fix and green after it. Exercise all affected paths and prove audio/transcript/stringified-error/endpoint/SAS/credential sentinels absent from properties/diagnostics. Run package `swift build && swift test`, `scripts/verify --layer VoxInfrastructure`, `scripts/verify`, and no-test-weakening review. |
| Edges | Depends only on merged PR00 or an explicitly approved byte-identical planning base; may run in parallel with PR01/atomic PR02 and PR05; PR06 waits for atomic PR02 plus PR04/PR05. |

### PR05 — VoxApplication arbitrary-error privacy

**Goal sentence**: After this PR, refinement failure telemetry cannot carry localized/free-form error or user text while domain/UI error propagation remains compatible.

- [ ] T007 [US2] Add a red/green privacy regression and remove/close localized refinement error fields in `Packages/VoxApplication/Sources/UseCases/DefaultRefinementUseCase.swift` and new `Packages/VoxApplication/Tests/UseCasesTests/DefaultRefinementTelemetryPrivacyTests.swift`

| Field | Contract |
|---|---|
| Owner / context | `VoxApplication`; `Packages/VoxApplication/tech-context.md` |
| Out of scope | Manifest/dependency selection; Infrastructure/Presentation/app/root files; Blob runtime; UI/domain error behavior; Loki endpoint/store; shared-telemetry |
| Interface impact | Use-case/domain interfaces and thrown errors remain; only arbitrary telemetry content is removed/replaced by a closed category |
| Acceptance / verification | Demonstrate sentinel test red then green. Exercise every failure path currently forwarding `localizedDescription`; prove transcript/refined/prompt/error/endpoint/SAS/credential markers absent while safe duration/count behavior and UI/domain errors remain. Run package `swift build && swift test`, `scripts/verify --layer VoxApplication`, `scripts/verify`, and no-test-weakening review. |
| Edges | Depends only on merged PR00 or an explicitly approved byte-identical planning base; may run in parallel with PR01/atomic PR02 and PR04; PR06 waits for atomic PR02 plus PR04/PR05. |

## Phase 2: PR06 — Dormant Blob deep module

**Goal sentence**: After this PR, VoxPocket's existing shared telemetry coordinator contains a tested but unadopted consent-capable Blob policy/configuration/store lifecycle plus persisted consent/identity state and host eligibility that default to zero-state and cannot emit a product event from production code.

- [ ] T008 [US1] Add persisted consent/identity state and extend the shared coordinator with the dormant Blob module/host-eligibility contract, source plist/XcodeGen settings, and focused tests in `Packages/VoxInfrastructure/Sources/Preferences/PreferencesStore.swift`, new `Packages/VoxInfrastructure/Tests/PreferencesTests/ProductTelemetryPreferencesTests.swift`, `VoxPocket/Config.xcconfig`, `VoxPocket/project.yml`, `VoxPocket/VoxPocket/Info.plist`, new `VoxPocket/VoxPocket/VoxPocketBlobTelemetry.swift`, new `VoxPocket/VoxPocket/BlobTelemetryConfiguration.swift`, new `VoxPocket/VoxPocket/BlobTelemetryHostEligibility.swift`, `VoxPocket/VoxPocket/TelemetryLifecycleCoordinator.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryPolicyTests.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryConfigurationTests.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryConsentTests.swift`, `VoxPocket/VoxPocketTests/TelemetryLifecycleCoordinatorTests.swift`, and `VoxPocket/VoxPocket.xcodeproj/project.pbxproj` only if regenerated output changes

| Field | Contract |
|---|---|
| Owner / context | `VoxInfrastructure` Preferences (`Packages/VoxInfrastructure/tech-context.md`); dormant `VoxPocketApp` module (`VoxPocket/tech-context.md`) |
| Out of scope | `ServiceContainer.swift`; `AppDelegate.swift`; `ContentView.swift`; `SettingsView.swift`; `VoxPocketApp.swift`; `MacOSAppScenes.swift`; Presentation source; production call sites/instrumentation; package manifests or non-enumerated package source; `.github/**`; Fastlane/scripts; Loki routing/store; real identifiers/credentials; new CLI executable |
| Interface impact | Preferences gains default-off consent and opaque install-identity records. The app module extends PR02's internal coordinator with typed `userAction`/`performance` commands, configuration/host-eligibility state, and a dedicated Blob store; source plist/build settings exist but no production Blob caller activates them. No second executor is introduced. |
| Acceptance | Tests precede code. With isolated `UserDefaults`, prove consent absence is off, first explicit opt-in creates one random UUID, and every later eligible load reuses that same UUID for the app installation's lifetime. Before first opt-in, valid config yields zero Blob service, identity creation/provider request, store, enqueue, or network activity. Model CLI/headless as negative host kinds and prove CLI/headless/test are ineligible for Blob construction even with valid synthetic config/consent. Invoke the `AzureBlobTelemetryService` bundle initializer only from coordinator-isolated asynchronous bootstrap and omit `maxDiskBytes` to accept the 50 MiB provider default. The shared coordinator is the sole host entry for Blob construction/product `track`/lifecycle `flush`; PR02 legacy provider construction/calls remain on its dedicated serial non-main executor. Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat; prove bundle startup heartbeat exists, product callers cannot emit it, and no second owner/host bypass exists. Admit only the two product shapes; reject all prohibited sentinels. Turning enablement off stops new admission/upload, cancels/disables the active generation under SDK semantics, retains non-evicted unconfirmed files, capacity ledger state, and the persisted UUID, performs no active-service identity request/use while off, and requires a later explicit opt-in to resume with that same UUID. Prove v1 has no install-ID Reset/rotation surface, requires no shared-telemetry API change, and performs no host parsing of adapter-private storage or catalog state. A separate missing/empty/unexpanded-configuration fixture runs independently of consent history, including a previous-opt-in state with a retained UUID, and proves zero identity creation/provider calls, store access, enqueue, or network calls; invalid present config yields fixed value-free Blob failure. |
| T008/T009 interface split | T008's “first explicit opt-in” evidence intentionally invokes its accepted coupled provisioning interface. The accepted T009 candidate adds the separate Settings consent-only interface. Its final correction keeps that Infrastructure seam storage-only and makes the Application use case the sole owner that persists the Boolean before requesting identity only for eligible interactive-app composition; missing/invalid configuration and excluded hosts therefore retain consent without identity. |
| SAS fixture | Accept `sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D`; assert names exactly `{sv,sr,si,spr,sig}`, `sr=c`, non-empty `si`/`sig`, `spr=https`, and no `sp`. Reject `sp=cw`, user-delegation keys including `skoid`, unknown names, or invalid `sr`. Static command fixture proves policy `--permissions c`; agents generate no token. |
| Verification | `swift build && swift test` from `Packages/VoxInfrastructure`; `scripts/verify --layer VoxInfrastructure`; focused app tests; `python3 scripts/ci/run_repository_tests.py app-python`; `scripts/verify --layer VoxPocketApp`; when generation occurs, retain one untouched raw output, record the actual command/version, and completely compare the T008-owned generated delta without assuming UUID stability or idempotency; structural search for coordinator-only host calls; store/request/diagnostic sentinel scan; `scripts/verify`. |
| Edges / gate | Depends on merged atomic PR02, PR04, and PR05. Blocks PR07/PR08. Owner approval required because `project.yml` is protected. |

## Phase 3: Parallel PR07 / PR08 after PR06

### PR07 — Consent-gated app adoption and lifecycle instrumentation

**Goal sentence**: After this PR, one Application-owned policy module orders consent-only persistence before eligible identity provisioning while the app shell supplies only validated facts and adapters, and all accepted Settings, product-event, lifecycle, exclusion, UUID-reuse, disable/retry, Loki, and atomic PR02 behavior remains intact.

- [ ] T009 [US1] Complete the frozen PR07 candidate through exactly `Packages/VoxApplication/Tests/UseCasesTests/ProductTelemetryActivationUseCaseTests.swift`, `Packages/VoxPresentation/Tests/UISharedTests/MacOSSettingsViewTests.swift`, `VoxPocket/VoxPocket/ServiceContainer.swift`, new `VoxPocket/VoxPocket/ProductTelemetryAssembly.swift`, `VoxPocket/VoxPocket/AppDelegate.swift`, `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTests.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTestSupport.swift`, XcodeGen-generated `VoxPocket/VoxPocket.xcodeproj/project.pbxproj`, `Packages/VoxPresentation/Sources/UIShared/ViewModels/ProductTelemetrySettingsViewModel.swift`, and `Packages/VoxPresentation/Tests/UISharedTests/ProductTelemetrySettingsViewModelTests.swift`

| Field | Contract |
|---|---|
| Owner / context | `VoxApplication` UseCases tests own executable activation-policy races (`Packages/VoxApplication/tech-context.md`); `VoxPresentation` UIShared Runtime owns committed display state in `ProductTelemetrySettingsViewModel`, and UIShared tests own its peer-convergence plus mounted Settings loading/default-suppression proofs (`Packages/VoxPresentation/tech-context.md`); `VoxPocketApp` owns private assembly, platform lifecycle wiring, App tests, and generated Xcode membership (`VoxPocket/tech-context.md`). The app continues consuming `VoxPresentation`, `VoxApplication`, and `VoxInfrastructure` through existing downward edges; no package imports the app and no new edge is added. |
| Exact paths / registration | T009 has ten exhaustive paths: preserve the historical eight-path Round 7 mechanical subset exactly as listed in `plan.md`, then change only `Packages/VoxPresentation/Sources/UIShared/ViewModels/ProductTelemetrySettingsViewModel.swift` and `Packages/VoxPresentation/Tests/UISharedTests/ProductTelemetrySettingsViewModelTests.swift` for peer convergence. The two Presentation files already exist in the candidate/project and require no registration. The selected-raw-output proof in `quickstart.md` remains scoped to the historical mechanical/generated-project subset. `VoxPocket/project.yml` stays byte-identical; if that subset regenerates, record `xcodegen --version`, use `xcodegen generate --spec project.yml` without installation/upgrade, bind the final project byte-for-byte to one untouched raw output, and permit only the two historical Swift memberships plus the two complete-graph UUID bijections for `Config.xcconfig` and its config-only `VoxPocket` group. No manual edit, normalization, canonicalizer, script, gate, stale/colliding mapping, or other generated difference is allowed. Any eleventh path or project-membership change stops for a new planning decision. |
| Out of scope | `Package.swift`; `project.yml`; Infrastructure/Preferences source/tests; Presentation views or any other Presentation production/test source; `BlobTelemetryConsentCompositionTests.swift`; `MacOSAppScenes.swift`; coordinator/event/configuration behavior; executor/provider; constitution/tech-context/gates; `.github/**`; Fastlane/scripts; credentials, release, TestFlight, CI dispatch, Round 9, implementation review, publication, approval, or merge; iPad multi-window investigation/delivery; generic identity/telemetry API; account/device identity; second state machine, manager, worker, executor, controller, protocol layer, dependency, global singleton, App test seam, telemetry event type, transport, storage location, or permission |
| Interface impact | Preserve every accepted public Application, Settings, Preferences, Blob/coordinator, `ServiceContainer`, and `AppDelegate` behavior. Keep both public Settings-model initializers and the request-phase `consentDidChange` payload/continuation contract. After the callback completes, the latest origin rereads its own persisted consent; only a value matching that latest intent may publish and send a value-free completion pulse on the existing notification name, while a mismatch retains the prior display and emits nothing. Loaded peers respond only by rereading their own preferences and never call `onConsentChanged`. The App observer continues ignoring pulses without the request fields. Preserve the d8 private-center App adapter, package-internal activation/Preferences gates, storage-only Preferences responsibility, and App-only validated-fact assembly. A package-internal deterministic notification/reader seam is allowed only in the model/test pair; no public abstraction or architecture change. |
| Structural acceptance | Measured candidate: `ServiceContainer.swift` 948 lines with a 162-line touched initializer; `BlobTelemetryInstrumentationTests.swift` 789 with 72-/65-line tests; `MacOSSettingsViewTests.swift` 437 with 104-/53-line tests; Application activation tests 357 with one exactly-50-line test; `AppDelegate.swift` 490 with touched launch/quick-record functions over the limit. Mechanically split the named surfaces so every changed/new Swift file, including the two-path Presentation closure, is `<800` physical lines and every changed/new initializer/function/test/helper is `<50`; retain a final path/line-count receipt. No assertion deletion counts as a size repair. |
| Sendable / Mutex | Keep unchecked conformance only for `QuickRecordRecordingUseCase`, `QuickRecordTranscriptionUseCase`, and `QuickRecordRefinementUseCase`, each with declaration-level proof that the immutable Combine subject bridge is the sole unchecked reason. Move transcription `language` and `snapshotGateActive` into typed `Synchronization.Mutex` state. Make stateless `QuickRecordClipboardService` checked `Sendable`; keep all other mutable doubles checked with shared state in `Mutex`. No unchecked wrapper around unsafe state. |
| Threat model | Preserve the existing app config/host validation boundary, consent/identity privacy boundary, and same-user local-filesystem trust for `UserDefaults` plus the app telemetry store. The Application policy receives only validated eligibility facts and necessary operations; it never holds or outputs a real SAS/endpoint/credential. The existing process-local notification channel is trusted only to invalidate display state: its completion pulse carries no Boolean/request/loading value, identity, configuration, endpoint, SAS, credential, content, or telemetry property, and grants no write, activation, admission, or upload authority. Each model rereads its own storage instance, so another store is never overwritten. Moved helpers add no external permission, persistence location, transport, or network channel; generator proof remains structure/hash metadata only and never reads real configuration or credentials. |
| Coverage preservation | Preserve every d8 Application race/readiness assertion, especially false→true `staleStartupCannotChangeFalseThenTrueWinnerSnapshot` with `[false, true]`, one UUID, winner snapshot/readiness, and no change after stale release. Preserve the existing Settings every-choice/latest-wins and default-off tests. Add deterministic separate opt-in and opt-out cases with two loaded models over the same store: gate the origin transition, assert the peer remains on its prior committed value, release persistence, then require both models to converge by their own rereads. Add rapid-choice/overlapping-refresh stale-result rejection and a different-store case; assert exactly one origin callback and zero peer writes, identity requests, activation, admission, or upload work. In mounted UI tests, keep the shortcuts and provider-loading/default-suppression cases plus privacy interactivity. Keep unchanged Infrastructure consent/identity and consent-composition excluded/invalid-host proofs. App XCTest retains real rapid start→release plus startup/recording/session/resign-active callers, all exact event/property/order/duration/identity/disable/re-enable assertions, and direct instrumentation only as supplemental evidence. |
| Real resign-active sequence | Build the default-off fixture/container/model/delegate; call real `applicationDidFinishLaunching`; await `waitForPendingStartup()` plus container telemetry startup completion; assert zero identity/construction/event; opt in through the real Settings model and await consent completion; call real `applicationWillResignActive`; wait for the first FIFO flush gate; record later `.settingsOpened` while suspended; release and await resign completion; call/await a second real resign-active flush; assert exactly `construct → flush → track product.user_action → flush`. Keep the broad lifecycle test and the Application false→true stale-startup test separately executable. |
| Acceptance / verification | Tests precede code. In VoxPresentation Package tests, use controlled continuations/gates rather than sleep to prove same-store opt-in/opt-out convergence only after persisted reread, pending-state stability, rapid-choice/stale-refresh latest-result behavior, exactly one origin callback with zero peer side effects, and different-store isolation. Run source parse only as supplemental syntax evidence. Run `swift build`/`swift test` for VoxApplication, VoxInfrastructure, and VoxPresentation plus their layer checks; Package success proves only owning Package behavior. For the unchanged historical mechanical subset, record actual XcodeGen command/version, prove `project.yml` byte identity, bind the final project to the selected raw output, and execute the complete two-membership/two-UUID-bijection graph comparison in `quickstart.md`; the incremental pair requires no generation. Then run app-python, `scripts/verify --layer VoxPocketApp`, `git diff --check`, and `scripts/verify`. App consumer compilation, executed App XCTest, unsigned synthetic Release/plist proof, and exact-head required CI remain separate evidence; cancelled compilation is no XCTest evidence, and aggregate success does not replace App-target failure. Do not mutate/review/publish the candidate or rerun CI until this planning revision independently passes and Team Lead grants fresh execution permission. |
| Edges | Depends on merged PR06; blocks PR09. |

### PR08 — Synthetic Release required-CI proof

**Goal sentence**: After this PR, required CI fails whenever synthetic Release plist expansion drifts, without signing, upload, credentials, or a network sender.

- [ ] T010 [US3] Add the unsigned Release verifier and CI wiring in `.github/workflows/ci.yml`, new `scripts/ci/verify_telemetry_release.sh`, and new `scripts/tests/test_blob_telemetry_release.py`

| Field | Contract |
|---|---|
| Owner / context | `_root support`; `docs/architecture/tech-context.md` |
| Out of scope | TestFlight workflow/Fastlane/docs; product/package/app/project/plist edits; real secrets/identifiers; signing/upload/network; trigger changes |
| Interface impact | Required CI gains a credential-free processed-Release-plist contract only |
| Acceptance / verification | Generate from project.yml, build unsigned Release with unmistakably fake non-routable settings, inspect the built plist for exact expansion/no `$(`, and guarantee no sender/sign/upload path. Run focused Python/helper tests, workflow syntax, app-python, the helper, `scripts/verify --policy`, `scripts/verify`, and full required CI. |
| Edges / gate | Depends on merged PR06; may run in parallel with PR07. Owner approval required for `.github/**` and `scripts/ci/**`. Blocks PR09. |

## Phase 4: PR09 — Manual TestFlight secure secret injection

**Goal sentence**: After this PR, authorized macOS TestFlight archives receive telemetry values only through a temporary untracked `0600` xcconfig while existing release behavior remains unchanged.

- [ ] T011 [US3] Add path-only xcconfig injection and packaging evidence in `.github/workflows/testflight.yml`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`, `scripts/tests/test_testflight_packaging.rb`, and `docs/testflight-release.md`

| Field | Contract |
|---|---|
| Owner / context | `_root support`; `docs/architecture/tech-context.md` |
| Out of scope | Product/package/app/project/plist edits; synthetic CI helper; workflow trigger broadening; iOS TestFlight; signing/team/bundle/build-number/upload/tag changes; live Azure calls; secret writes by agents; real identifiers/values; local archive/dispatch |
| Interface impact | Existing manual macOS lane gains one temporary credential-file path; no runtime API |
| Acceptance | Workflow creates one untracked xcconfig under the runner temp directory, applies/verifies `0600`, writes the two GitHub secret values without printing them, and passes only the path via `-xcconfig`. No value appears in xcargs, command-line environment assignments, printable arguments, messages, or logs. Fastlane cleanup is in `ensure`; workflow cleanup is `always`; both cover success/failure/cancellation. Raw and shell/percent-escaped synthetic sentinels are absent from captured Release-path logs. Preserve manual `workflow_dispatch`, checkout target, signing, numbering, upload, macOS-only scope, iOS disablement, and release tags. |
| Owner commands | PR body contains exactly the placeholder command templates in `plan.md`: key-auth stored-policy creation with permission `c`/explicit expiry; HTTPS-only `generate-sas --policy-name` piped to `gh secret set TELEMETRY_BLOB_SAS`; and interactive `gh secret set TELEMETRY_BLOB_ENDPOINT`. No `--as-user`; no `cw`; no real identifier in Git. |
| Verification | Focused Python/Ruby tests; app-python; `packaging-ruby`; workflow/Ruby syntax; raw+escaped log scan; missing-input/mode/cleanup assertions; `scripts/verify --policy`; `scripts/verify`; required CI. |
| Edges / gate | Depends on merged PR07 and PR08. Owner approval required for `.github/**` and `fastlane/**`. Blocks production evidence. |

## Phase 5: Owner-controlled production evidence

- [ ] T012 [US1] After every extant implementation PR (PR01, PR02, and PR04–PR09) merges, Owner provisioning, fresh release authorization, and separate tester Settings opt-in, record one approved-action TestFlight/read-only Blob result without repository edits

| Field | Contract |
|---|---|
| Owner / context | Owner provisioning/release plus Team Lead read-only evidence; no repository writer |
| In scope | Owner executes Decision 1A commands with real values, sets both secrets, and explicitly authorizes the existing manual release; tester separately enables “Send usage data” and performs one approved action; Team Lead records exact merged/workflow revision, run reference, TestFlight build number, blob name, and terminal category |
| Out of scope | Agent Azure/GitHub mutation; repository edits; early/implicit dispatch; payload download; endpoint/account/container/SAS disclosure; permission widening; failed-run repair inside this task |
| Acceptance / verification | Stored policy is time-bounded/create-only, generated SAS is provider-compatible, release authorization is not treated as consent, separate tester opt-in plus one approved action produces at least one blob, read-only listing records name only, and evidence contains no payload or credential. Failure routes through Team Lead to the original implementation owner. |
| Edges | Depends on all implementation PRs merged, applicable Owner approvals, both secrets, a new explicit Owner release authorization, and separate tester Settings opt-in before the evidence action. Remains externally blocked until every condition holds. |

## Dependencies and execution order

```text
T000 / PR00 reviewed planning landing
  -> PR01 T001 required app-test CI
       -> atomic PR02 {T005 + T002–T004 + T013} exact 0.2.0 / off-main migration
  -> {PR04 T006 || PR05 T007} privacy repairs
{atomic PR02 || PR04 || PR05}
       -> PR06 T008 dormant Blob module
            -> {PR07 T009 || PR08 T010}
                 -> PR09 T011 secure TestFlight injection
                      -> Owner provisioning + fresh release authority + separate tester opt-in
                           -> T012 production evidence
```

PR01→atomic PR02 is the ordered safety chain: required CI exists before the combined exact-`0.2.0`/off-main regression, and no old-`0.1.0` intermediate claims a flush barrier. T005 and T002–T004/T013 are layer-scoped tasks within one inseparable candidate, not internal publication steps. PR04 and PR05 may proceed independently after PR00; PR06 waits for atomic PR02 plus PR04/PR05. PR07 and PR08 may then run in parallel after PR06. Every later PR waits for its declared base to merge before final merge; any rebase/retarget changes the SHA and invalidates prior review/verification. T012 is not an implementation task and merge alone never authorizes it.

## Tracker disposition for the atomic slice

- `MY-1857` / T001 remains the prerequisite required-CI slice.
- `MY-1856` becomes the sole atomic PR02 implementation slice for T005 plus all T002–T004/T013 scope. The original Fullstack Engineer remains the only eventual writer, and no implementation resumes until this exact planning revision has independent spec-gate `PASS` and Team Lead gives explicit execution approval.
- `MY-1832` remains `blocked`/parked as superseded standalone-PR03 history. Preserve its delivery metadata, prior evidence, and task history; do not dispatch a second writer, publish its route, or silently drop T002–T004/T013.
- `MY-1833` / T006 and `MY-1834` / T007 remain completed privacy prerequisites. `MY-1835` / T008 remains backlog, but its dependency is remapped from standalone MY-1832 to the atomic MY-1856 slice plus those completed privacy prerequisites.

## Acceptance coverage matrix

| Spec acceptance | Task(s) |
|---|---|
| US1/AC1 | T008, T009, T012 |
| US1/AC2, US1/AC3, US1/AC4, US1/AC6 | T008, T009 |
| US1/AC7, US1/AC8 | T008, T009 |
| US1/AC5 | T012 |
| US2/AC1 | T006–T009 |
| US2/AC2 | T006, T007 |
| US2/AC3, US2/AC4 | T008 |
| US2/AC5 | T008, T010, T011 |
| US2/AC6 | T008, T009 |
| US3/AC1 | T002–T004, T013 |
| US3/AC6 | T001, T005 |
| US3/AC7 | T002–T004, T008, T009, T013 |
| US3/AC2 | T002–T007, T009, T013 |
| US3/AC3 | T008, T010 |
| US3/AC4 | T011 |
| US3/AC5 | T000–T011, T013 per-PR contract |
| FR-001 | T002–T004, T013 |
| FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 | T008, T009 |
| FR-008, FR-009 | T006–T009 |
| FR-010, FR-011, FR-012, FR-013 | T008, T009 |
| FR-014 | T011 |
| FR-015 | T005–T011 |
| FR-016 | T010, T011 |
| FR-017 | T008–T011 |
| FR-018 | T011 |
| FR-019 | T000–T011, T013 per-PR contract |
| FR-020 | T012 |
| FR-021 | T008, T009 |
| FR-022, FR-023, FR-024 | T008, T009 |
| FR-025 | T001, T005 |
| FR-026 | T002–T004, T008, T009, T013 |
| SC-001 | T006–T009 |
| SC-002 | T008 |
| SC-003 | T010, T011 |
| SC-004 | T001–T011, T013 |
| SC-005 | T000–T011, T013 per-PR contract |
| SC-006 | T012 |
| SC-007 | T008, T009 |
| SC-008 | T001, T005, T008, T009, T013 |
| RB-001 | T006, T007 |
| RB-002 | T008, T009 |
| RB-003 | T001–T011, T013 |
| RB-004 | T001, T005 |
| RB-005 | T002–T004, T008, T009, T013 |

Compatibility and RB-001–RB-005 are enforced at every applicable PR: PR01 adds only the required existing-test gate; atomic PR02 makes only the Lead-approved inseparable exact-`0.2.0` selection/current-truth plus off-main legacy change and accepts provider-default bounded retention; PR04/PR05 remove only approved unsafe values; PR06 stays dormant/disabled while extending the same coordinator with isolated Blob consent/identity and excluded-host contracts; PR07 activates only valid configuration plus current explicit consent and preserves atomic PR02's seam; PR08 is fake Release proof only; PR09 alone adds real-secret ingress without changing triggers/signing/upload/platform scope.

## Format validation

- Total tasks: 14 (`T000`–`T013`): planning 1; required app-test CI 1; runtime adaptation 1; dependency/current-truth migration 4; privacy 2; dormant app 1; adoption 1; synthetic CI 1; TestFlight injection 1; production evidence 1.
- Every executable row uses native `- [ ] Txxx [US#]` syntax and exact files/paths.
- Every implementation task declares its owning layer/support scope(s), in/out paths, interface impact, local acceptance, verification, and dependencies; T008 is the dormant consent-capable module/state slice, while T009 preserves d8's package-policy/App-integration ownership, the exact eight-path Round 7 mechanical/XcodeGen subset, and one incremental two-path Presentation peer-convergence closure with no new product abstraction.
- The graph is acyclic. T001 gates the atomic PR02 candidate containing T005/T013/T002–T004; those five layer-scoped tasks share one writer and final head, with no publishable internal edge. T006 and T007 may proceed after PR00 in parallel with that chain; T008 waits for atomic PR02 plus PR04/PR05.
- PR01 keeps CI governance separate. Lead decision `loki02v1` intentionally combines non-trivial runtime adaptation with the dependency/pin/current-truth move in atomic PR02 because the old-`0.1.0` intermediate cannot meet FR-025. Privacy, Blob consent/adoption, synthetic CI, and TestFlight governance remain separate, and no task combines implementation authority with Owner provisioning/release dispatch.
