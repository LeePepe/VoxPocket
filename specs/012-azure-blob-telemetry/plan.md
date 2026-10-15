# Implementation Plan: Privacy-safe Azure Blob product telemetry

**Feature**: `012-azure-blob-telemetry` | **Date**: 2026-10-15 | **Spec**: [`spec.md`](./spec.md)

**Planning branch**: `agent/planner-lead/38bb392a6f3b`

**Baseline**: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

**Input**: MY-1818 issue revision 1, Team Lead planning handoff, repository evidence, and shared-telemetry integration contract

## Summary

Adopt the immutable shared-telemetry Azure Blob adapter as a second, explicitly routed product-telemetry path without changing the existing Loki event service or Loki log sink. VoxPocket exposes only two typed product events, rejects non-allowlisted/private data before persistence, owns a dedicated retry store through one serialized non-`@MainActor` lifecycle coordinator, and fails disabled/closed when build configuration is absent/invalid. Real endpoint/SAS values enter only an explicitly Owner-authorized macOS TestFlight archive; required CI proves the processed Release plist with synthetic values. Existing arbitrary localized/stringified error values are removed from Loki telemetry under the accepted privacy authority and guarded by sentinel tests.

## Technical Context

**Language/version**: Swift 6.2 packages/app; Python 3.11+ repository tests; Ruby/Fastlane; YAML/GitHub Actions; XcodeGen

**Primary dependencies**: shared-telemetry/LokiKit (reviewed Blob API at `0ffdbc82a5fbd76f54e49127b0d30a4fb8666e95`, exact `0.2.0` if published before implementation publication); existing SwiftUI/AppKit app shell; shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`

**Storage**: dedicated Application Support Blob adapter catalog/event/sidecar/capacity files; existing Loki event/log stores remain separate and untouched

**Testing**: Swift Testing/XCTest package and app tests; repository Python/Ruby packaging fixtures; XcodeGen idempotency; unsigned synthetic macOS Release build with processed-plist inspection; policy/layer/full gates

**Target platform**: macOS app and manual macOS TestFlight release; iOS remains compile/test only and receives no TestFlight enablement

**Project type**: layered Swift desktop/mobile app with SwiftPM packages, XcodeGen app shell, and root release/CI support

**Performance goals**: no synchronous Blob file I/O on `@MainActor`; one serialized admission owner; UI/lifecycle submission returns without waiting on file I/O; one active flush maximum

**Constraints**: no audio/transcript/refined/prompt/error/credential telemetry; no generic strings; no live Azure CI; no committed real identifier; no implicit release dispatch; no queue migration; failed/cancelled events stay retryable; no test/gate weakening

**Scale/scope**: three dependency consumers, two current privacy boundaries, one app-lifetime Blob runtime, four closed user-action labels, one performance operation, two plist/build settings, and one Owner-gated release path

## Constitution Check — Before Research

| Principle / repository rule | Result | Plan response |
|---|---|---|
| I Immutability | PASS | Product events are immutable typed values; adapter files change only through the single owner. No existing user data is mutated. |
| II Layer direction | PASS | Infrastructure and Application harden their own telemetry boundaries; Presentation changes only its dependency manifest; app-shell composition owns Blob integration; root support owns CI/release. No package imports the app. |
| III Concurrency safety | PASS | Synchronous adapter persistence is isolated in a non-`@MainActor` actor. Main-actor callers submit asynchronously; flushes serialize/join. |
| IV Privacy of voice/text | PASS | Exact allowlists and sentinel tests reject voice/text/prompt/error/credential content before accepted state; existing unsafe error fields are removed. |
| V Secrets/vendor hygiene | PASS | No real endpoint/SAS/resource identifier is committed or used in PR tests. Real values enter only from GitHub secrets during an authorized TestFlight archive and are never printed. |
| VI Boundary validation | PASS | Plist, adapter policy, labels, numeric bounds, dependency revision, and processed Release output are validated fail-closed. |
| XcodeGen source of truth | PASS | `VoxPocket/project.yml` owns build settings/file membership; generated project changes are produced only by the pinned generator and checked for idempotency. |
| TestFlight-only production delivery | PASS | Local/PR verification is unsigned, synthetic, and non-networked. Production evidence remains post-merge and Owner-authorized. |
| Existing behavior preserved | PASS | Loki services/stores/routing and release semantics remain, except the explicitly authorized removal of arbitrary error strings. |
| Important paths need Owner | PASS | Package manifests, project.yml, CI/Fastlane/scripts/contexts use existing CODEOWNERS gates and an important non-Draft PR. |

No constitutional exception is requested.

## Research Decisions

The evidence and alternatives are in [`research.md`](./research.md). Binding decisions:

1. **R-001 — Immutable repository-wide dependency**: use one full reviewed SHA while `v0.2.0` is absent; if the exact tag appears before implementation publication, move every consumer/guard together and record its resolved SHA.
2. **R-002 — Separate transports and stores**: Blob neither decorates nor mirrors Loki; it owns a dedicated store and must not migrate/delete Loki data.
3. **R-003 — Closed event vocabulary**: typed constructors expose only `product.user_action` and `product.performance`; heartbeat is SDK-owned.
4. **R-004 — Off-main serialized lifecycle**: one non-`@MainActor` actor owns synchronous admission, ordered persistence, joined flush, retry retention, and shutdown/resign-active coordination.
5. **R-005 — Disabled before state**: missing/empty/unexpanded config creates no identity/store/network state; present-invalid config closes only Blob with a fixed diagnostic.
6. **R-006 — Release-only real configuration**: source plist uses build references; PR uses synthetic Release proof; TestFlight receives opaque GitHub secret values without disclosure.
7. **R-007 — Privacy fix at owners**: Application/Infrastructure replace or remove arbitrary error strings and add boundary-specific sentinel regressions.
8. **R-008 — Compatibility first**: preserve Debug/local behavior, manual macOS TestFlight, iOS compile/test-only behavior, signing/build/upload/tag logic, and every existing gate.
9. **R-009 — Owner-gated important changes**: do not bypass package/project/workflow/Fastlane/script ownership.
10. **R-010 — External production slice**: Owner provisioning/dispatch and Team Lead read-only blob evidence are separate from implementation completion.

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
- No presentation source change is needed: app-shell seams already own the accepted settings/full-panel/quick-record actions. Presentation telemetry, UI, and view-model behavior are preservation surfaces.

### VoxPocketApp Blob runtime

- Add `VoxPocketBlobTelemetry.swift`, `BlobTelemetryConfiguration.swift`, and `BlobTelemetryLifecycleCoordinator.swift` under `VoxPocket/VoxPocket/`; add `BlobTelemetryPolicyTests.swift`, `BlobTelemetryConfigurationTests.swift`, `BlobTelemetryLifecycleCoordinatorTests.swift`, and `BlobTelemetryInstrumentationTests.swift` under `VoxPocket/VoxPocketTests/`; register them only through `VoxPocket/project.yml`.
- The runtime reads exact plist keys, validates disabled/invalid/enabled state, creates a non-personal install UUID only for valid first-use/reset, opens a Blob-only Application Support directory, and retains one service/coordinator for app lifetime.
- A non-`@MainActor` actor is the only synchronous adapter caller and performs enabled-service/store construction through actor-isolated asynchronous bootstrap rather than its caller-side initializer. `ServiceContainer`, `AppDelegate`, and `MacOSAppScenes` schedule typed commands; they never construct an enabled store or call adapter `track` directly.
- Record `app_launch` duration and the four accepted actions at successful semantic boundaries. Request flush after startup telemetry, recording/session completion, and macOS resign-active. Join the active flush and retain failed/cancelled pending files.
- Add exact source plist substitutions and synthetic Release settings through `Info.plist`, `Config.xcconfig`, and `project.yml`. Existing Loki construction, injection, event routing, log sink, and stores remain separate.

### Root dependency and release support

- Update `scripts/ci/fetch-external-deps.sh` and `scripts/tests/test_app_logging.py` to require the one selected revision across all manifests and validate the external consumer contract.
- Extend credential-free app/release tests and repository discovery as needed without removing existing assertions.
- Add a required unsigned synthetic Release build/check that inspects the processed app plist for exact fake expansion and no unresolved reference, signing, upload, or Azure contact.
- Extend `.github/workflows/testflight.yml` and `fastlane/Fastfile` only to pass the two GitHub secrets into the existing macOS archive as opaque build settings. Preserve manual `workflow_dispatch`, checkout target, signing, numbering, upload, iOS disablement, and tag behavior.
- Update `docs/testflight-release.md` with placeholder-only operator semantics; the PR body, not committed documentation, carries the issue-accepted resource-specific Owner commands.

## Implementation Slices

### Slice D — Freeze the dependency contract

Resolve the immutable tag/SHA at implementation publication, validate the provider consumer fixture, then move the root guard and the Infrastructure/Application/Presentation manifests together. Mixed dependency state cannot proceed to app work.

### Slice US2 — Remove unsafe existing telemetry values

Land red/green privacy tests and content-free replacements independently in VoxInfrastructure and VoxApplication. Preserve safe existing Loki events, use-case behavior, and UI error presentation.

### Slice US1 — Add the Blob product path

Build the typed contract and disabled/config/store/lifecycle actor in VoxPocketApp; instrument startup and the four approved actions at app-shell semantic boundaries; wire retry-safe flush triggers; add full app contract tests. This slice is independently testable with an in-memory receiver/store fixture and no credentials.

### Slice US3 — Prove build/release wiring and compatibility

Add exact XcodeGen/plist settings, synthetic Release proof, and secret-only TestFlight injection while preserving every existing release invariant. Run package/app/release/policy/full gates and XcodeGen idempotency on the frozen candidate.

### Slice Delivery — Reviewed publication

Obtain independent content review and explicit publication permission for the frozen uncommitted candidate, then publish the same tree as a non-Draft important PR. Bind local/remote/PR SHA, dependency resolution, AC evidence, Owner commands, CODEOWNERS approval, and required checks.

### Slice Production — Owner-controlled evidence

After merge, secret provisioning, and explicit Owner release authorization, the existing manual workflow produces one used macOS TestFlight build. Team Lead records only the build number, run/revision, blob name, and terminal category from read-only evidence.

## Acceptance Traceability

| Acceptance / requirement | Slice | Tasks | Evidence |
|---|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC6; FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-010, FR-011, FR-012, FR-015, FR-021 | US1 | T005 | typed contract tests; disabled/invalid fixtures; actor ordering/join/retry tests; startup/action/flush integration; unchanged Loki assertions |
| US1/AC5; FR-020; SC-006 | Production | T008 | explicit Owner authorization; exact merged/run revision; TestFlight build number; read-only blob name; no payload/credential evidence |
| US2/AC1; FR-005, FR-006, FR-007, FR-008, FR-015 | US1/US2 | T002, T003, T005 | policy whole-event rejection and Infrastructure/Application/app-shell privacy sentinels |
| US2/AC2; FR-008, FR-009; RB-001 | US2 | T002, T003 | red/green localized/stringified-error tests and closed/omitted replacement fields |
| US2/AC3, US2/AC4; FR-010, FR-011 | US1 | T005 | missing/empty/unexpanded zero-state fixture and present-invalid fixed-diagnostic fixture |
| US2/AC5; FR-014, FR-015, FR-016, FR-018, FR-019 | US3/Delivery | T006, T007 | secret-absence scans/fixtures; synthetic Release processed plist; preserved gates; PR contract |
| US3/AC1; FR-001 | D | T001–T004 | provider consumer check, exact tag/SHA record, three matching manifests and root guard |
| US3/AC2; FR-002, FR-003, FR-008, FR-009 | US2/US1 | T002, T003, T005 | Loki construction/routing/store regressions and privacy-only removed-behavior diff |
| US3/AC3, US3/AC4; FR-013, FR-014, FR-015, FR-016, FR-017 | US3 | T005, T006 | XcodeGen source settings, processed synthetic plist, opaque TestFlight secret injection, unchanged release invariants |
| US3/AC5; FR-018, FR-019 | Delivery | T007 | important non-Draft PR, accepted Owner actions, exact head, Owner approval, required checks, no bypass |
| SC-001 | US1/US2 | T002, T003, T005 | all supplied prohibited sentinels rejected before persistence/transport |
| SC-002 | US1 | T005 | zero identity/store/enqueue/network counts for disabled Debug/Release fixtures |
| SC-003 | US3 | T006 | both synthetic processed values expanded; no real value/unresolved reference in repository/output |
| SC-004 | All repository slices | T001–T007 | focused layer, policy, repository, `--all`, and exact-candidate review evidence |
| SC-005 | Delivery | T007 | Owner-approved important PR and required checks on identical local/remote/PR head |

Every stable acceptance criterion and functional requirement maps to an owned task and evidence surface. Production-only acceptance remains explicitly external rather than being claimed by repository tests.

## Verification Strategy

[`quickstart.md`](./quickstart.md) is the executable verification contract. Required implementation evidence:

1. recheck `v0.2.0`, record the selected 40-character provider revision, and pass the provider external-consumer fixture;
2. demonstrate the new privacy tests red against the baseline unsafe fields, then green without assertion weakening;
3. pass the VoxInfrastructure, VoxApplication, and VoxPresentation layer gates independently;
4. pass app fixtures for typed allowlists, prohibited sentinels, disabled/invalid config, off-main ordered admission, joined flush, failure/cancellation retention, action instrumentation, and unchanged Loki paths;
5. generate from `VoxPocket/project.yml`, prove zero generated drift, and inspect an unsigned synthetic Release app's processed plist;
6. pass credential-free Python/Ruby release fixtures, `scripts/verify --policy`, `scripts/verify`, `scripts/verify --all`, and `git diff --check`;
7. freeze one candidate for exact independent content review before any commit/push/PR;
8. after publication permission, prove reviewed tree identity and equality of local SHA, remote branch OID, and PR `headRefOid`;
9. preserve manual release authority; production proof occurs only after merge and a new explicit Owner authorization.

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

Packages/VoxInfrastructure/
├── Package.swift
├── Sources/TranscriptionKit/
│   ├── VoxPocketTelemetryEventName.swift
│   └── WhisperKitTranscriber.swift
└── Tests/TranscriptionKitTests/

Packages/VoxApplication/
├── Package.swift
├── Sources/UseCases/DefaultRefinementUseCase.swift
└── Tests/UseCasesTests/

Packages/VoxPresentation/
└── Package.swift

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
│   └── BlobTelemetryLifecycleCoordinator.swift
└── VoxPocketTests/
    ├── BlobTelemetryPolicyTests.swift
    ├── BlobTelemetryConfigurationTests.swift
    ├── BlobTelemetryLifecycleCoordinatorTests.swift
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
```

**Structure decision**: existing package layers own only their manifests/privacy boundaries; VoxPocketApp owns composition, typed product events, store/config/lifecycle, and instrumentation; root support owns cross-repository dependency guards and release/CI behavior. Generated Xcode project files are outputs, never hand-edited sources.

## Constitution Check — After Design

PASS with no exception. The design preserves package direction, makes the synchronous file boundary structurally non-main, rejects private/free-form data before accepted state, uses only synthetic credential-free CI, keeps XcodeGen authoritative, isolates Blob files from Loki, and separates Owner-controlled release evidence from implementation authority. The authorized arbitrary-error removal is explicit and test-covered; every other legacy/release behavior remains a preservation surface.

## Dependencies and External Gates

- Repository base: VoxPocket `9fddff22af2c9f693e0a90155b224a5fb41dbf06`.
- Repo contract: shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`.
- Provider dependency: reviewed shared-telemetry `0ffdbc82a5fbd76f54e49127b0d30a4fb8666e95`, superseded only by exact `v0.2.0` if it exists before implementation publication.
- Planning gate: AI Reviewer exact-revision PASS before Team Lead implementation dispatch.
- Candidate gate: AI Reviewer exact frozen-tree PASS plus explicit publication permission before commit/push/PR.
- Important-path gate: Owner approval and required checks on the exact non-Draft PR head.
- Production gate: merged PR, Owner-created write-only SAS, both GitHub secrets, and a new explicit Owner authorization before manual TestFlight dispatch.

## Risks and Escalation Conditions

| Risk | Mitigation / escalation |
|---|---|
| `v0.2.0` appears or resolves differently | Recheck once immediately before publication, move all consumers atomically, record the resolved SHA, and rerun dependency/provider checks. Mixed state blocks. |
| SDK API differs from reviewed docs | Stop and return exact compiler/provider-contract evidence; do not invent an adapter wrapper or widen shared-telemetry scope. |
| Synchronous I/O leaks onto `@MainActor` | Structural typed coordinator seam plus actor/order tests. Any direct adapter call from UI/lifecycle code blocks review. |
| Privacy policy requires arbitrary strings | Reject the event or add a new Owner-approved closed label. Never sanitize/redact after persistence. |
| Store lease/capacity/rollback behavior is incompatible | Preserve all files, stop the Blob owner, and return exact adapter evidence. Never reuse/delete Loki or Blob persisted state manually. |
| XcodeGen produces unexpected drift | Stop with generator version and diff. Do not hand-edit the generated project or absorb unrelated output. |
| Synthetic Release proof needs signing/network | Treat as a design failure and return to the app/root-support owner; do not introduce secrets or live access. |
| Secret value appears in logs/tests/diff | Stop publication, rotate if real, remove the exposure through the owning release seam, and rerun all absence evidence. |
| Important approval/check is missing | Keep the PR unmerged in Owner review; never bypass CODEOWNERS/ruleset protection. |
| Owner has not provisioned or authorized production | Repository delivery may complete, but T008 remains blocked and no workflow is dispatched or blob listed. |

## Complexity Tracking

No constitutional violation is requested. The additional actor/runtime is justified by the provider's synchronous persistence boundary and deepens the app interface: callers submit two typed event variants and lifecycle commands without knowing configuration, identity, store, policy, or transport details.
