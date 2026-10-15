---

description: "Single-goal PR graph with layer-scoped tasks for privacy-safe Azure Blob product telemetry"

---

# Tasks: Privacy-safe Azure Blob product telemetry

**Input**: Design documents from `specs/012-azure-blob-telemetry/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/product-telemetry-contract.md`, `quickstart.md`, `checklists/requirements.md`

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**Organization**: PR00 lands the exact reviewed plan. PR01 is one atomic dependency-only PR composed of layer-scoped tasks. PR01, PR02, and PR03 each depend only on PR00 and may run concurrently because their paths and outputs are independent; PR04 waits for all three. PR02–PR07 each have one observable goal and independently leave `main` working. Every PR freezes, verifies, receives independent exact-tree review/publication permission, publishes only that tree, proves local/remote/PR-head equality, passes required CI, and obtains applicable CODEOWNERS/Owner approval. Evidence never transfers to another or rebased head.

## Per-PR delivery contract

Every PR task below includes this acceptance in addition to its task-local checks:

1. Declare the base and start the PR `Intent` with its one-sentence observable goal.
2. Run focused checks plus `scripts/verify` and `git diff --check` at the frozen candidate; run `scripts/verify --all` for forced-full-selection changes when practical and require all server checks on the exact head.
3. Obtain independent AI Reviewer spec/architecture `PASS` and explicit publication permission for that exact tree.
4. Publish only the reviewed tree, then prove `git rev-parse HEAD`, the remote branch OID, and PR `headRefOid` are byte-identical.
5. Complete every PR-template section, preserve RB-001–RB-003, and wait for applicable CODEOWNERS/Owner approval and required checks.
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
| Blocking edges | No implementation PR starts from an unreviewed/unpublished plan. PR01, PR02, and PR03 each depend on merged PR00, or on an explicitly approved base containing byte-identical reviewed artifacts; the three may then run concurrently. |

## Phase 1: Parallel PR01 / PR02 / PR03 after PR00

### PR01 — Dependency-only immutable selection

**Goal sentence**: After this PR, every VoxPocket consumer and current authority resolves shared-telemetry exact version `0.2.0` with no product-behavior change.

**Independent test**: annotated `v0.2.0` peels to the reviewed commit, the provider version-mode consumer fixture passes, all three packages build/test, repository guards and the enumerated active truth/projection set contain exact `0.2.0` with no revision selector, explicitly historical feature evidence remains labelled historical, and full repository verification passes.

- [ ] T001 [US3] Update root dependency guards and protected authorities/projections in `AGENTS.md`, `README.md`, `.specify/memory/constitution.md`, `docs/architecture/tech-context.md`, `docs/architecture/packages-architecture.md`, `scripts/ci/fetch-external-deps.sh`, `scripts/tests/test_app_logging.py`, `docker/telemetry/README.md`, and the dependency-only comment in `.github/workflows/testflight.yml`
- [ ] T002 [US3] Update the VoxInfrastructure manifest/projections in `Packages/VoxInfrastructure/Package.swift`, `Packages/VoxInfrastructure/tech-context.md`, `Packages/VoxInfrastructure/OVERVIEW.md`, and `Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/README.md`
- [ ] T003 [US3] Update the VoxApplication dependency in `Packages/VoxApplication/Package.swift`
- [ ] T004 [US3] Update the VoxPresentation dependency in `Packages/VoxPresentation/Package.swift`
- [ ] T005 [US3] Update the VoxPocketApp dependency projection in `VoxPocket/tech-context.md`

#### PR01 task metadata

| Task | Owner / context | In scope and interface | Out of scope | Task-local acceptance and verification | Edges |
|---|---|---|---|---|---|
| T001 | `_root support`; `docs/architecture/tech-context.md` | Root guard/current truth and a deliberate constitution dependency-fact amendment; no runtime API | Package/app source, privacy adaptation, Blob runtime, functional CI/Fastlane change, real identifiers/credentials, shared-telemetry edits | Require SwiftPM `exact: "0.2.0"`; verify annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` peels to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, record both OIDs as integrity evidence only, forbid branch/revision selectors or fallback, and run provider `external_consumer.py --version 0.2.0`. Constitution amendment states rule (immutable selected provider), reason (Blob API), migration (three manifests + guards + current projections atomically), bumps patch version `1.2.0`→`1.2.1` with 2026-10-15 Last Amended metadata, and states no red-line weakening. Run focused root tests, `scripts/verify --policy`, and `scripts/verify`. Search the enumerated current-truth paths for zero old selection or revision selector; exclude `spec.md`/`research.md` historical baseline evidence explicitly rather than using a blind repo search. | T001–T005 form one atomic PR head; PR01 depends only on PR00 and may run concurrently with PR02/PR03. |
| T002 | `VoxInfrastructure`; `Packages/VoxInfrastructure/tech-context.md` | Manifest and current Infrastructure dependency projections only | All Infrastructure source/privacy tests/behavior | Exact selection equals T001; `swift build && swift test` from `Packages/VoxInfrastructure`; `scripts/verify --layer VoxInfrastructure`; no source/test diff | Dependency-order-independent within PR01, but executed by PR01's sole writer; atomic with T001/T003–T005. |
| T003 | `VoxApplication`; `Packages/VoxApplication/tech-context.md` | Manifest only | Application source/privacy tests/behavior | Exact selection equals T001; `swift build && swift test` from `Packages/VoxApplication`; `scripts/verify --layer VoxApplication`; no source/test diff | Dependency-order-independent within PR01, but executed by PR01's sole writer; atomic with siblings. |
| T004 | `VoxPresentation`; `Packages/VoxPresentation/tech-context.md` | Manifest only | Presentation source/tests/UI behavior | Exact selection equals T001; `swift build && swift test` from `Packages/VoxPresentation`; `scripts/verify --layer VoxPresentation`; no source/test diff | Dependency-order-independent within PR01, but executed by PR01's sole writer; atomic with siblings. |
| T005 | `VoxPocketApp`; `VoxPocket/tech-context.md` | Current external-dependency projection only | App source/project/plist/behavior | Exact selection equals T001; context audit and `scripts/verify --layer VoxPocketApp`; no app implementation diff | Dependency-order-independent within PR01, but executed by PR01's sole writer; atomic with siblings. |

**PR01 publication**: important/Owner-gated due constitution, AGENTS, architecture, contexts, manifests, `scripts/ci/**`, and `.github/**`. No dependency slice may merge partially.

### PR02 / PR03 — Existing privacy repairs

#### PR02 — VoxInfrastructure arbitrary-error privacy

**Goal sentence**: After this PR, transcription failure telemetry cannot carry arbitrary stringified error or voice/text content while safe event semantics remain.

- [ ] T006 [US2] Add a red/green privacy regression and remove/close arbitrary transcription error fields in `Packages/VoxInfrastructure/Sources/TranscriptionKit/VoxPocketTelemetryEventName.swift`, `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift`, and new `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitTelemetryPrivacyTests.swift`

| Field | Contract |
|---|---|
| Owner / context | `VoxInfrastructure`; `Packages/VoxInfrastructure/tech-context.md` |
| Out of scope | Manifest/context/dependency selection; Blob/app/Application/Presentation/root changes; Loki endpoint/store; UI/domain error behavior; shared-telemetry |
| Interface impact | Existing telemetry name and safe duration/count/outcome semantics remain; arbitrary `reason` becomes a closed content-free category or is omitted |
| Acceptance / verification | Demonstrate sentinel test red before the source fix and green after it. Exercise all affected paths and prove audio/transcript/stringified-error/endpoint/SAS/credential sentinels absent from properties/diagnostics. Run package `swift build && swift test`, `scripts/verify --layer VoxInfrastructure`, `scripts/verify`, and no-test-weakening review. |
| Edges | Depends only on merged PR00 or an explicitly approved byte-identical planning base; may run in parallel with PR01 and PR03; PR04 waits for all three. |

#### PR03 — VoxApplication arbitrary-error privacy

**Goal sentence**: After this PR, refinement failure telemetry cannot carry localized/free-form error or user text while domain/UI error propagation remains compatible.

- [ ] T007 [US2] Add a red/green privacy regression and remove/close localized refinement error fields in `Packages/VoxApplication/Sources/UseCases/DefaultRefinementUseCase.swift` and new `Packages/VoxApplication/Tests/UseCasesTests/DefaultRefinementTelemetryPrivacyTests.swift`

| Field | Contract |
|---|---|
| Owner / context | `VoxApplication`; `Packages/VoxApplication/tech-context.md` |
| Out of scope | Manifest/dependency selection; Infrastructure/Presentation/app/root files; Blob runtime; UI/domain error behavior; Loki endpoint/store; shared-telemetry |
| Interface impact | Use-case/domain interfaces and thrown errors remain; only arbitrary telemetry content is removed/replaced by a closed category |
| Acceptance / verification | Demonstrate sentinel test red then green. Exercise every failure path currently forwarding `localizedDescription`; prove transcript/refined/prompt/error/endpoint/SAS/credential markers absent while safe duration/count behavior and UI/domain errors remain. Run package `swift build && swift test`, `scripts/verify --layer VoxApplication`, `scripts/verify`, and no-test-weakening review. |
| Edges | Depends only on merged PR00 or an explicitly approved byte-identical planning base; may run in parallel with PR01 and PR02; PR04 waits for all three. |

## Phase 2: PR04 — Dormant Blob deep module

**Goal sentence**: After this PR, VoxPocket contains a tested but unadopted consent-capable Blob policy/configuration/store/coordinator plus persisted consent/identity state and host eligibility that default to zero-state and cannot emit a product event from production code.

- [ ] T008 [US1] Add persisted consent/identity state and the dormant Blob module/host-eligibility contract, source plist/XcodeGen settings, and focused tests in `Packages/VoxInfrastructure/Sources/Preferences/PreferencesStore.swift`, new `Packages/VoxInfrastructure/Tests/PreferencesTests/ProductTelemetryPreferencesTests.swift`, `VoxPocket/Config.xcconfig`, `VoxPocket/project.yml`, `VoxPocket/VoxPocket/Info.plist`, new `VoxPocket/VoxPocket/VoxPocketBlobTelemetry.swift`, new `VoxPocket/VoxPocket/BlobTelemetryConfiguration.swift`, new `VoxPocket/VoxPocket/BlobTelemetryHostEligibility.swift`, new `VoxPocket/VoxPocket/BlobTelemetryLifecycleCoordinator.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryPolicyTests.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryConfigurationTests.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryConsentTests.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryLifecycleCoordinatorTests.swift`, and `VoxPocket/VoxPocket.xcodeproj/project.pbxproj` only if regenerated output changes

| Field | Contract |
|---|---|
| Owner / context | `VoxInfrastructure` Preferences (`Packages/VoxInfrastructure/tech-context.md`); dormant `VoxPocketApp` module (`VoxPocket/tech-context.md`) |
| Out of scope | `ServiceContainer.swift`; `AppDelegate.swift`; `ContentView.swift`; `SettingsView.swift`; `VoxPocketApp.swift`; `MacOSAppScenes.swift`; Presentation source; production call sites/instrumentation; package manifests or non-enumerated package source; `.github/**`; Fastlane/scripts; Loki routing/store; real identifiers/credentials; new CLI executable |
| Interface impact | Preferences gains default-off consent and opaque install-identity records. The app module gains internal typed `userAction`/`performance` commands, configuration/host-eligibility state, dedicated store, and coordinator; source plist/build settings exist but no production caller activates them. |
| Acceptance | Tests precede code. With isolated `UserDefaults`, prove consent absence is off, first explicit opt-in creates one random UUID, later eligible loads reuse it, and Reset replaces it without enabling consent or exposing the value. Valid config without consent yields zero service/identity/store/enqueue/network. Model CLI/headless as negative host kinds (the repository has no production CLI target) and prove CLI/headless/test are ineligible for service construction even with valid synthetic config/consent. Invoke the exact `AzureBlobTelemetryService(bundle:app:build:version:privacy:storeDirectory:isEnabled:identityProvider:configuration:maxDiskBytes:)` only from actor-isolated bootstrap. The actor is sole host entry for construction/product `track`/lifecycle `flush`. Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat; prove bundle startup heartbeat exists, product callers cannot emit it, and no second owner/host bypass exists. Admit only the two product shapes; reject all prohibited sentinels. Turning enablement off stops new admission/upload, cancels/disables the active generation under SDK semantics, retains unconfirmed files, and requires a later explicit opt-in to resume. Reset rotates the enabled generation so newly admitted events use only the replacement identity. Missing/empty/unexpanded config yields zero identity/store/enqueue/network; invalid present config yields fixed value-free Blob failure. Use a dedicated store and retain unconfirmed files. |
| SAS fixture | Accept `sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D`; assert names exactly `{sv,sr,si,spr,sig}`, `sr=c`, non-empty `si`/`sig`, `spr=https`, and no `sp`. Reject `sp=cw`, user-delegation keys including `skoid`, unknown names, or invalid `sr`. Static command fixture proves policy `--permissions c`; agents generate no token. |
| Verification | `swift build && swift test` from `Packages/VoxInfrastructure`; `scripts/verify --layer VoxInfrastructure`; focused app tests; `python3 scripts/ci/run_repository_tests.py app-python`; `scripts/verify --layer VoxPocketApp`; repository-pinned XcodeGen regenerate/no-diff; structural search for coordinator-only host calls; store/request/diagnostic sentinel scan; `scripts/verify`. |
| Edges / gate | Depends on merged PR01, PR02, and PR03. Blocks PR05/PR06. Owner approval required because `project.yml` is protected. |

## Phase 3: Parallel PR05 / PR06 after PR04

### PR05 — Consent-gated app adoption and lifecycle instrumentation

**Goal sentence**: After this PR, only the consented interactive app constructs Blob telemetry and emits the accepted product events/lifecycle flushes; consent defaults off, disable stops admission/upload without deleting pending files, install identity is first-opt-in/reused/resettable, excluded hosts construct nothing, and Loki behavior remains unchanged.

- [ ] T009 [US1] Add Settings controls, adopt the Blob coordinator only in the interactive app, and instrument semantic boundaries in new `Packages/VoxPresentation/Sources/UIShared/ViewModels/ProductTelemetrySettingsViewModel.swift`, `Packages/VoxPresentation/Sources/UIShared/Views/MacOSSettingsView.swift`, `Packages/VoxPresentation/Sources/UIShared/Views/MeRootView.swift`, new `Packages/VoxPresentation/Tests/UISharedTests/ProductTelemetrySettingsViewModelTests.swift`, `Packages/VoxPresentation/Tests/UISharedTests/MacOSSettingsViewTests.swift`, new `Packages/VoxPresentation/Tests/UISharedTests/ProductTelemetrySettingsViewTests.swift`, `VoxPocket/VoxPocket/ServiceContainer.swift`, `VoxPocket/VoxPocket/AppDelegate.swift`, `VoxPocket/VoxPocket/MacOSAppScenes.swift`, `VoxPocket/VoxPocketTests/AppStartupTests.swift`, `VoxPocket/VoxPocketTests/QuickRecordingWindowLifecycleTests.swift`, `VoxPocket/VoxPocketTests/VoxPocketTests.swift`, `VoxPocket/VoxPocketUITests/VoxPocketUITests.swift`, new `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTests.swift`, and new `VoxPocket/VoxPocketTests/BlobTelemetryConsentCompositionTests.swift`

| Field | Contract |
|---|---|
| Owner / context | `VoxPresentation` UIShared (`Packages/VoxPresentation/tech-context.md`); `VoxPocketApp` composition (`VoxPocket/tech-context.md`) |
| Out of scope | Project/plist/build settings; Infrastructure consent schema/module internals; package manifests or non-enumerated package source; `.github/**`; Fastlane/scripts; TestFlight secrets; Loki replacement; account/device-derived identity; any CLI/headless/test-host construction; new executable/CLI target; iOS TestFlight |
| Interface impact | macOS Settings and the cross-platform privacy surface gain the exact “Send usage data” toggle and Reset action backed by the T008 preference contract; only interactive production app assembly uses the already-tested internal typed module. No generic/public telemetry API is added. |
| Acceptance / verification | Tests precede code. Prove both Settings surfaces load default-off state independently of Blob construction, persist explicit opt-in, disable immediately, and replace identity through Reset without displaying/exposing its value. Existing unrelated Settings access may remain but cannot make Blob-service construction a side effect. Prove CLI/headless negative host-kind fixtures and real test-host composition construct no Blob service even with valid synthetic configuration and consent true; do not add a CLI executable. Retain at most one live coordinator/service generation for a consented interactive app; record launch performance and settings/full-panel/quick-record start/stop only at successful semantic boundaries; flush after startup, recording/session completion, and macOS resign-active; preserve ordering/join/retry and the T008 pending-file disable/reset contracts. Missing/invalid config remains disabled/closed. Prove unchanged Loki construction/routing/log sink/store/safe events and no legacy fan-out. Run `swift build && swift test` and `scripts/verify --layer VoxPresentation`, focused app/UI fixtures, app-python, `scripts/verify --layer VoxPocketApp`, `scripts/verify`, and required app CI. |
| Edges | Depends on merged PR04; blocks PR07. |

### PR06 — Synthetic Release required-CI proof

**Goal sentence**: After this PR, required CI fails whenever synthetic Release plist expansion drifts, without signing, upload, credentials, or a network sender.

- [ ] T010 [US3] Add the unsigned Release verifier and CI wiring in `.github/workflows/ci.yml`, new `scripts/ci/verify_telemetry_release.sh`, and new `scripts/tests/test_blob_telemetry_release.py`

| Field | Contract |
|---|---|
| Owner / context | `_root support`; `docs/architecture/tech-context.md` |
| Out of scope | TestFlight workflow/Fastlane/docs; product/package/app/project/plist edits; real secrets/identifiers; signing/upload/network; trigger changes |
| Interface impact | Required CI gains a credential-free processed-Release-plist contract only |
| Acceptance / verification | Generate from project.yml, build unsigned Release with unmistakably fake non-routable settings, inspect the built plist for exact expansion/no `$(`, and guarantee no sender/sign/upload path. Run focused Python/helper tests, workflow syntax, app-python, the helper, `scripts/verify --policy`, `scripts/verify`, and full required CI. |
| Edges / gate | Depends on merged PR04; may run in parallel with PR05. Owner approval required for `.github/**` and `scripts/ci/**`. Blocks PR07. |

## Phase 4: PR07 — Manual TestFlight secure secret injection

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
| Edges / gate | Depends on merged PR05 and PR06. Owner approval required for `.github/**` and `fastlane/**`. Blocks production evidence. |

## Phase 5: Owner-controlled production evidence

- [ ] T012 [US1] After PR01–PR07 merge, Owner provisioning, fresh release authorization, and separate tester Settings opt-in, record one approved-action TestFlight/read-only Blob result without repository edits

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
  -> {PR01 T001–T005 || PR02 T006 || PR03 T007}
       -> PR04 T008 dormant Blob module
            -> {PR05 T009 || PR06 T010}
                 -> PR07 T011 secure TestFlight injection
                      -> Owner provisioning + fresh release authority + separate tester opt-in
                           -> T012 production evidence
```

PR01, PR02, and PR03 are separate parallel PRs after PR00 because their owned paths and outputs are independent; PR04 waits for all three. PR05 and PR06 may then run in parallel after PR04. Every later PR waits for its declared base to merge before final merge; any rebase/retarget changes the SHA and invalidates prior review/verification. T012 is not an implementation task and merge alone never authorizes it.

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
| US3/AC1 | T001–T005 |
| US3/AC2 | T006, T007, T009 |
| US3/AC3 | T008, T010 |
| US3/AC4 | T011 |
| US3/AC5 | T000–T011 per-PR contract |
| FR-001 | T001–T005 |
| FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 | T008, T009 |
| FR-008, FR-009 | T006–T009 |
| FR-010, FR-011, FR-012, FR-013 | T008, T009 |
| FR-014 | T011 |
| FR-015 | T006–T011 |
| FR-016 | T010, T011 |
| FR-017 | T009–T011 |
| FR-018 | T011 |
| FR-019 | T000–T011 per-PR contract |
| FR-020 | T012 |
| FR-021 | T008, T009 |
| FR-022, FR-023, FR-024 | T008, T009 |
| SC-001 | T006–T009 |
| SC-002 | T008 |
| SC-003 | T010, T011 |
| SC-004 | T001–T011 |
| SC-005 | T000–T011 per-PR contract |
| SC-006 | T012 |
| SC-007 | T008, T009 |

Compatibility and RB-001, RB-002, and RB-003 are enforced at every applicable PR: PR01 changes only selection truth; PR02/PR03 remove only approved unsafe values; PR04 stays dormant/disabled while adding the isolated consent/identity and excluded-host contracts; PR05 activates only valid configuration plus current explicit consent in the interactive app and adds only the required Settings controls/composition; PR06 is fake Release proof only; PR07 alone adds real-secret ingress without changing triggers/signing/upload/platform scope.

## Format validation

- Total tasks: 13 (`T000`–`T012`): planning 1; dependency 5 in one atomic PR; privacy 2; dormant app 1; adoption 1; synthetic CI 1; TestFlight injection 1; production evidence 1.
- Every executable row uses native `- [ ] Txxx [US#]` syntax and exact files/paths.
- Every implementation task declares its owning layer/support scope(s), in/out paths, interface impact, local acceptance, verification, and dependencies; T008 is the dormant consent-capable module/state slice and T009 is the directionally valid Presentation/app adoption slice.
- The graph is acyclic. T002–T005 are dependency-order-independent but execute sequentially through PR01's sole branch writer; PR01/T001–T005, PR02/T006, and PR03/T007 are independent parallel PRs after PR00, and PR04 waits for all three.
- No PR combines dependency selection, behavioral privacy/product adaptation, synthetic CI, or TestFlight governance; no task combines implementation authority with Owner provisioning/release dispatch.
