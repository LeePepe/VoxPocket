---

description: "Layer-scoped task graph for privacy-safe Azure Blob product telemetry"

---

# Tasks: Privacy-safe Azure Blob product telemetry

**Input**: Design documents from `specs/012-azure-blob-telemetry/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/product-telemetry-contract.md`, `quickstart.md`, `checklists/requirements.md`

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**Organization**: Dependency selection is frozen first; package-layer privacy/dependency work then proceeds by owner; VoxPocketApp owns the Blob runtime; root support owns release/CI; publication and production evidence remain separate gates. Every executable task has one layer or explicit support scope.

## Phase 1: Dependency contract (blocking prerequisite)

**Goal**: select one immutable shared-telemetry revision containing the reviewed Blob API and make the repository guard/docs authoritative before any consumer changes.

**Independent test**: provider external-consumer verification passes for the selected full revision; root guards and authority docs name one selection; tag/revision evidence is recorded without changing a package manifest.

- [ ] T001 [US3] Freeze the shared-telemetry selection and update root dependency guards/authority documentation

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `_root support`; context `docs/architecture/tech-context.md` |
| Vertical slice | Dependency prerequisite / US3 |
| Files in scope | `scripts/ci/fetch-external-deps.sh`; `scripts/tests/test_app_logging.py`; `AGENTS.md`; `README.md`; `docs/architecture/tech-context.md`; `docker/telemetry/README.md` |
| Files out of scope | All three `Packages/*/Package.swift`; package source/tests; app source/project/plist; `.github/**`; `fastlane/**`; real credentials/resource identifiers; shared-telemetry repository changes |
| Interface impact | Changes the root dependency guard from v0.1.0 to one immutable selection containing the public Blob API; no runtime product interface |
| Task-local acceptance | Immediately before implementation publication, query the provider tag and record the outcome. If exact `v0.2.0` exists, use it and record its resolved 40-character SHA; otherwise use full reviewed revision `0ffdbc82a5fbd76f54e49127b0d30a4fb8666e95`. Run the provider's `sdks/swift/scripts/external_consumer.py --revision <sha>`. Update every in-scope pin statement/guard consistently, preserve AppleUITesting sibling behavior, use no branch/short/mixed pin, and introduce no real cloud identifier. |
| Verification | Provider external-consumer command; `scripts/ci/fetch-external-deps.sh` after T002–T004; focused `python3 -B scripts/tests/test_app_logging.py`; pin search proves old SHA absent from authoritative in-scope paths and selected revision present. |
| Blocking edges | None. T002–T004 consume the selected revision; T005 and T006 cannot start until all four are consistent. |

**Checkpoint**: one reviewed immutable provider selection is documented; no package consumer is yet changed by this task.

---

## Phase 2: Package consumers and existing privacy boundaries (Priority: P1)

**Goal**: move each package in its owning layer and remove only the accepted arbitrary-error telemetry while preserving safe Loki behavior.

**Independent test**: each layer builds/tests independently at the selected revision; Infrastructure/Application privacy sentinels fail on baseline and pass after their local fix; Presentation source remains unchanged.

- [ ] T002 [P] [US2] Upgrade VoxInfrastructure and replace stringified transcription error telemetry with a closed content-free outcome

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `VoxInfrastructure`; context `Packages/VoxInfrastructure/tech-context.md` |
| Vertical slice | US2 privacy + dependency prerequisite |
| Files in scope | `Packages/VoxInfrastructure/Package.swift`; `Packages/VoxInfrastructure/Sources/TranscriptionKit/VoxPocketTelemetryEventName.swift`; `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift`; new `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitTelemetryPrivacyTests.swift`; `Packages/VoxInfrastructure/tech-context.md`; `Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/README.md` |
| Files out of scope | Application/Presentation/app/root files; Blob construction/store/lifecycle; Loki endpoint/store changes; UI error handling; model/deployment taxonomy expansion; shared-telemetry edits |
| Interface impact | Package dependency selection changes; existing public telemetry event-name compatibility remains. The unsafe `reason` payload is removed or replaced by a reviewed closed category; no arbitrary string interface is added. |
| Task-local acceptance | Write a red sentinel test before the source fix. Prove audio/transcript/stringified-error/endpoint/SAS/credential sentinels do not enter emitted properties or diagnostics. Preserve safe event name, durations/counts/outcome semantics and transcriber behavior. Update layer dependency/context truth to T001's exact selection. Do not pass `String(describing:)`, `localizedDescription`, model/deployment free text, or other arbitrary strings to telemetry. |
| Verification | From `Packages/VoxInfrastructure`: `swift build && swift test`; repository `scripts/verify --layer VoxInfrastructure`; pin equality with T001; diff review proves no unrelated source/test weakening. |
| Blocking edges | Depends on T001. Runs in parallel with T003 and T004 because paths/layers do not overlap. Blocks T005/T007. |

- [ ] T003 [P] [US2] Upgrade VoxApplication and replace localized refinement error telemetry with a closed content-free outcome

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `VoxApplication`; context `Packages/VoxApplication/tech-context.md` |
| Vertical slice | US2 privacy + dependency prerequisite |
| Files in scope | `Packages/VoxApplication/Package.swift`; `Packages/VoxApplication/Sources/UseCases/DefaultRefinementUseCase.swift`; new `Packages/VoxApplication/Tests/UseCasesTests/DefaultRefinementTelemetryPrivacyTests.swift` |
| Files out of scope | Infrastructure/Presentation/app/root files; UI/domain error presentation; session behavior except necessary preservation assertions; Blob construction/store/lifecycle; Loki endpoint/store changes; shared-telemetry edits |
| Interface impact | Package dependency selection changes. Existing use-case/domain interfaces and thrown errors remain; only the telemetry payload stops carrying arbitrary localized error text. |
| Task-local acceptance | Write a red sentinel test before the source fix. Exercise every refinement failure path currently forwarding `error.localizedDescription`; prove transcript/refined-text/prompt/localized-error/endpoint/SAS/credential markers are absent from telemetry while closed failure category and safe duration/count semantics remain. UI/domain error propagation is byte-for-behavior compatible. Update the manifest to T001's exact selection. |
| Verification | From `Packages/VoxApplication`: `swift build && swift test`; repository `scripts/verify --layer VoxApplication`; pin equality with T001; no removed/weakened existing assertion. |
| Blocking edges | Depends on T001. Runs in parallel with T002 and T004. Blocks T005/T007. |

- [ ] T004 [P] [US3] Upgrade the VoxPresentation dependency manifest without changing presentation behavior

### T004 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `VoxPresentation`; context `Packages/VoxPresentation/tech-context.md` |
| Vertical slice | Dependency prerequisite / US3 compatibility |
| Files in scope | `Packages/VoxPresentation/Package.swift` only |
| Files out of scope | All `Packages/VoxPresentation/Sources/**` and tests except read-only verification; other packages; app/root files; UI instrumentation; new telemetry API |
| Interface impact | Dependency-resolution-only change; public/source behavior remains unchanged. |
| Task-local acceptance | Move the manifest to T001's exact selection. Prove presentation source/test bytes are unchanged and the package resolves/builds/tests with the upgraded product. Do not add Blob calls to a view/view model or any direct synchronous persistence on `@MainActor`. |
| Verification | From `Packages/VoxPresentation`: `swift build && swift test`; repository `scripts/verify --layer VoxPresentation`; manifest equality with T001 and source/test no-diff evidence. |
| Blocking edges | Depends on T001. Runs in parallel with T002 and T003. Blocks T005/T007. |

**Checkpoint**: all consumers resolve one provider revision, privacy violations are removed at their owners, and the existing packages pass independently.

---

## Phase 3: User Story 1 — Typed Blob product telemetry in the app (Priority: P1)

**Goal**: a configured app records only the two accepted product-event shapes through a dedicated retryable store and serialized off-main lifecycle, while missing/invalid configuration stays safe.

**Independent test**: app fixtures admit the two valid shapes; reject every prohibited sentinel before accepted state; prove disabled zero-state, invalid fail-closed, non-main ordered persistence, joined flush, retry retention, and unchanged Loki routing without credentials/network.

- [ ] T005 [US1] Implement and test the VoxPocketApp typed Blob runtime, configuration, lifecycle, product instrumentation, and XcodeGen wiring

### T005 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `VoxPocketApp`; context `VoxPocket/tech-context.md` |
| Vertical slice | US1 plus app-side US2/US3 compatibility |
| Files in scope | `VoxPocket/Config.xcconfig`; `VoxPocket/project.yml`; `VoxPocket/VoxPocket/Info.plist`; `VoxPocket/VoxPocket/ServiceContainer.swift`; `VoxPocket/VoxPocket/AppDelegate.swift`; `VoxPocket/VoxPocket/MacOSAppScenes.swift`; new `VoxPocket/VoxPocket/VoxPocketBlobTelemetry.swift`; new `VoxPocket/VoxPocket/BlobTelemetryConfiguration.swift`; new `VoxPocket/VoxPocket/BlobTelemetryLifecycleCoordinator.swift`; `VoxPocket/VoxPocketTests/AppStartupTests.swift`; `VoxPocket/VoxPocketTests/QuickRecordingWindowLifecycleTests.swift`; `VoxPocket/VoxPocketTests/VoxPocketTests.swift`; new `VoxPocket/VoxPocketTests/BlobTelemetryPolicyTests.swift`; new `VoxPocket/VoxPocketTests/BlobTelemetryConfigurationTests.swift`; new `VoxPocket/VoxPocketTests/BlobTelemetryLifecycleCoordinatorTests.swift`; new `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTests.swift`; `VoxPocket/tech-context.md`; XcodeGen-generated project output only as generated by the pinned repository command |
| Files out of scope | Package source/manifests; `.github/**`; `fastlane/**`; `scripts/**`; existing Loki event/log store ownership or routing; settings UI/consent feature; iOS TestFlight/background entitlements; arbitrary event dictionary API; real identifiers/credentials |
| Interface impact | Adds an app-internal deep module with typed `userAction`/`performance` submission and lifecycle flush commands. Adds build inputs `TELEMETRY_BLOB_ENDPOINT`/`TELEMETRY_BLOB_SAS` and processed plist keys; no public package API. |
| Task-local acceptance | Tests precede implementation. Implement exact contract values from `contracts/product-telemetry-contract.md`; one dedicated Application Support store; non-personal UUID only for valid first-use/reset; one app-lifetime non-`@MainActor` actor owning adapter/store; enabled service/store construction through actor-isolated asynchronous bootstrap; ordered synchronous admission off main; one joined flush; retry retention after failure/cancellation. Missing/empty/unexpanded config yields zero identity/store/enqueue/network; present-invalid yields fixed value-free Blob-only failure. Instrument successful app launch duration, settings open, full-panel open, quick-record start/stop at app-shell semantic boundaries; flush after startup event, recording/session end, and macOS resign-active. Existing Loki service/log sink/store/routing and safe events remain; no legacy fan-out. `Info.plist` contains the two exact substitutions. XcodeGen is the only membership/settings writer. |
| Verification | App unit/integration fixtures for all contract clauses; `python3 scripts/ci/run_repository_tests.py app-python`; `scripts/verify --layer VoxPocketApp`; repository-pinned XcodeGen regenerate/no-diff proof; structural search shows adapter synchronous persistence reachable only inside the non-main coordinator; sentinel-byte scan of fixture stores/requests/diagnostics. |
| Blocking edges | Depends on T001–T004 so the provider API and all consumers are consistent. Blocks T006 and T007. |

**Checkpoint**: US1/AC1–AC4/AC6 and local US2 configuration/privacy acceptance are independently demonstrable without credentials or Azure.

---

## Phase 4: User Story 3 — Synthetic Release and Owner-gated TestFlight wiring (Priority: P1)

**Goal**: required CI catches plist-expansion/secret-wiring drift while the real values remain confined to the existing manual macOS TestFlight archive.

**Independent test**: an unsigned synthetic Release app contains both fully expanded fake plist values, no unresolved reference, and makes no sender request; Python/Ruby fixtures prove TestFlight passes opaque secret references without printing values and preserves every existing release invariant.

- [ ] T006 [US3] Add credential-free Release proof and secret-only TestFlight build-setting injection under root-support/Owner gates

### T006 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `_root support`; context `docs/architecture/tech-context.md` |
| Vertical slice | US3 release/CI compatibility |
| Files in scope | `.github/workflows/ci.yml`; `.github/workflows/testflight.yml`; `fastlane/Fastfile`; new `scripts/ci/verify_telemetry_release.sh`; new `scripts/tests/test_blob_telemetry_release.py`; `scripts/tests/test_testflight_freshness.py`; `scripts/tests/test_testflight_packaging.rb`; `docs/testflight-release.md` |
| Files out of scope | Product/package/app/project/plist files; workflow trigger broadening; iOS TestFlight; signing/team/bundle/build-number/upload/tag changes; live Azure calls; GitHub secret writes; real values/identifiers; policy/test removal or skip |
| Interface impact | Required CI gains an unsigned synthetic Release processed-plist contract. Existing manual macOS TestFlight lane gains two opaque build-setting inputs sourced only from GitHub secrets. |
| Task-local acceptance | CI uses unmistakably fake non-routable values, generates/builds Release unsigned, inspects the built app plist for exact expansion, rejects unresolved `$(`, and neither signs/uploads/sends nor records a credential. TestFlight remains `workflow_dispatch` on the existing target and validates only presence without value disclosure. Fastlane shell-safely passes opaque environment references/values to the archive, never interpolates them into messages, and preserves signing, build numbering, upload, iOS disablement, and tag behavior. Python/Ruby tests prove secret names/wiring, no value logging, missing-input failure, existing assertions, and no local release dispatch. Documentation uses placeholders only; issue-accepted resource-specific Owner commands remain PR-body content. |
| Verification | `python3 -B scripts/tests/test_blob_telemetry_release.py`; `python3 scripts/ci/run_repository_tests.py app-python`; Fastlane `packaging-ruby` command from `quickstart.md`; execute the synthetic helper; workflow/Ruby syntax; `scripts/verify --policy`; secret/identifier absence checks. |
| Blocking edges | Depends on T005's exact app build/plist interface. Blocks T007. Owner/CODEOWNERS review is mandatory before merge. |

**Checkpoint**: US3/AC3–AC4 and SC-003 have credential-free evidence; no real release has been authorized or run.

---

## Phase 5: Exact-candidate delivery (Priority: P1)

**Goal**: verify, independently review, and publish one unchanged candidate with complete AC/Owner evidence.

**Independent test**: all focused/layer/policy/full gates pass on the frozen tree; AI Reviewer grants exact content PASS/publication permission; reviewed tree equals published commit tree; local/remote/PR head SHAs match; important PR has Owner approval and required checks.

- [ ] T007 [US1] Verify and publish the exact reviewed implementation candidate as a non-Draft important PR

### T007 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `_root support` integration/evidence; no product-code writer |
| Vertical slice | US1/US2/US3 delivery |
| Files in scope | Verification evidence and PR body generated from `.github/pull_request_template.md`; no repository edit expected except implementation-owned corrections returned to T001–T006 |
| Files out of scope | Repairing another layer inside this task; merge; Owner secret creation; TestFlight dispatch; Azure access; test/gate weakening; force/admin bypass; stale-SHA evidence |
| Interface impact | None; binds the reviewed contracts to one publishable candidate and exact PR head. |
| Task-local acceptance | Run the provider check; all three package layer gates; app Python/app layer; synthetic Release helper; packaging Ruby; XcodeGen no-diff; `scripts/verify --policy`; `scripts/verify`; `scripts/verify --all`; `git diff --check`. Freeze the uncommitted candidate and obtain AI Reviewer exact content PASS plus explicit publication permission. Publish only the unchanged tree. The non-Draft important PR records: selected dependency/tag outcome and resolved SHA; every US/AC evidence row; compatibility/RB-001–RB-003 analysis; dedicated-store/rollback behavior; exact accepted Owner write-only SAS and two secret-add commands; no real identifier in repository artifacts; local/remote/PR SHA equality; CODEOWNERS approval and required checks. Any failure returns to the owning task and invalidates/repeats evidence. |
| Verification | Fresh command logs from `quickstart.md`; reviewer verdict tied to a tree manifest; `git rev-parse HEAD`; remote branch OID; PR `headRefOid`; changed-file/layer ownership map; Owner approval and required-check evidence on that exact head. |
| Blocking edges | Depends on T001–T006. Content review blocks publication; publication/Owner/check gates block merge. T008 remains separately externally blocked. |

**Checkpoint**: repository implementation can be delivered/merged through the normal PR path. Production event evidence is not yet claimed.

---

## Phase 6: Owner-controlled production evidence (externally blocked)

**Goal**: after reviewed merge and explicit authority, prove one real TestFlight product event reached the existing container without exposing payload or credentials.

**Independent test**: one used TestFlight build has an exact run/revision/build number and at least one blob name from a read-only listing; the evidence contains no payload or sensitive value.

- [ ] T008 [US1] After merge, Owner provisioning, and explicit release authorization, record one TestFlight/read-only Blob result

### T008 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | Owner-controlled provisioning/release plus Team Lead read-only evidence; no repository writer |
| Vertical slice | US1 production acceptance |
| Files in scope | Execution-only use of `.github/workflows/testflight.yml`; issue evidence record |
| Files out of scope | Repository edits; early/implicit dispatch; SAS/secret creation by an agent; Azure resource mutation; payload download; credential/log disclosure; widening SAS permissions; repairing a failed run in this task |
| Interface impact | None; exercises the merged reviewed contract. |
| Task-local acceptance | Preconditions are merged exact PR, Owner-created time-bounded create/write-only SAS, both GitHub secrets, and a fresh explicit Owner authorization for this manual run. After the Owner-authorized macOS TestFlight build is installed/used once, Team Lead performs only the accepted read-only listing and records exact merged/run revision, workflow URL/reference, build number, blob name, and terminal category. Record no payload, endpoint/account/container identifier, SAS, or secret-bearing output. Failure routes through Team Lead to the original implementation owner. |
| Verification | Owner authorization/provisioning references; exact merged/workflow SHA; TestFlight build number; read-only blob-name evidence; terminal result; absence of payload/credential content. |
| Blocking edges | Depends on T007, PR Manager merge, Owner provisioning, and a new explicit Owner release authorization. It remains blocked and undispatched until all conditions hold. |

## Dependencies and execution order

```text
T001 root dependency selection/guard
  ├─> T002 VoxInfrastructure manifest + privacy
  ├─> T003 VoxApplication manifest + privacy
  └─> T004 VoxPresentation manifest-only upgrade
          T002 + T003 + T004
                    -> T005 VoxPocketApp Blob runtime
                         -> T006 root CI/TestFlight wiring
                              -> T007 full verification + frozen review + PR
                                   -> Owner approval/checks + PR Manager merge
                                        -> Owner provisioning + explicit release authorization
                                             -> T008 production evidence
```

- T002, T003, and T004 are parallel because each owns a different package layer and separate files.
- T005 waits for all consumers so no app integration resolves a mixed provider graph.
- T006 consumes T005's exact plist/build-setting interface; it does not repair app code.
- T007 owns evidence only. Any code/test defect returns to T001–T006 and requires a new frozen review.
- T008 is not an implementation task and is never authorized by merge alone.

## Acceptance coverage matrix

| Spec acceptance | Task(s) |
|---|---|
| US1/AC1 | T005, T008 |
| US1/AC2, US1/AC3, US1/AC4, US1/AC6 | T005, T007 |
| US1/AC5 | T008 |
| US2/AC1 | T002, T003, T005 |
| US2/AC2 | T002, T003 |
| US2/AC3, US2/AC4 | T005 |
| US2/AC5 | T001, T005–T007 |
| US3/AC1 | T001–T004 |
| US3/AC2 | T002, T003, T005, T007 |
| US3/AC3, US3/AC4 | T005, T006 |
| US3/AC5 | T007 |
| FR-001 | T001–T004 |
| FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 | T005 |
| FR-008, FR-009 | T002, T003, T005 |
| FR-010, FR-011, FR-012, FR-013 | T005 |
| FR-014, FR-015, FR-016, FR-017 | T005, T006, T007 |
| FR-018, FR-019 | T007 |
| FR-020 | T008 |
| FR-021 | T005, T007 |
| SC-001 | T002, T003, T005 |
| SC-002 | T005 |
| SC-003 | T006 |
| SC-004 | T001–T007 |
| SC-005 | T007 |
| SC-006 | T008 |

Every user-story acceptance and FR/SC has an owning task. Compatibility and RB-001–RB-003 are enforced by T002/T003/T005 preservation tests and T007 exact-diff review.

## Implementation strategy

1. Freeze and validate the provider contract once (T001).
2. Move package consumers by layer and make privacy regressions red/green before app work (T002–T004).
3. Add the deep typed/off-main Blob module in the composition layer (T005).
4. Wire synthetic and real-release build settings only after the host interface is stable (T006).
5. Verify/review the whole candidate before publication and bind evidence to one exact PR head (T007).
6. Leave real provisioning/release/listing blocked for explicit post-merge Owner control (T008).

## Format validation

- Total tasks: 8 (dependency: 1; package/privacy: 3; app: 1; CI/release: 1; delivery: 1; production: 1).
- Every executable row uses `- [ ] Txxx [US#]` and exact paths.
- Every task declares one owning layer/support scope, in/out paths, interface impact, local acceptance, verification, and dependencies.
- The graph is acyclic; only T002–T004 are valid parallel tasks.
- No task combines repository implementation authority with Owner provisioning or release dispatch.
