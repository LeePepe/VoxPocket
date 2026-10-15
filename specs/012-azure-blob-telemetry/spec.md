# Feature Specification: Privacy-safe Azure Blob product telemetry

**Feature Branch**: `012-azure-blob-telemetry`

**Created**: 2026-10-15

**Status**: Ready for spec-gate review

**Input**: MY-1818 issue revision 1, Team Lead planning handoff, and VoxPocket `main` at `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

## User Scenarios & Testing

### User Story 1 - Observe a real TestFlight product event (Priority: P1)

As the product owner, I can use a configured macOS TestFlight build once and find a privacy-approved product event in the existing telemetry container, so product usage is observable without creating another cloud resource.

**Why this priority**: The workflow outcome is one real product event delivered from VoxPocket; local or synthetic evidence alone does not complete it.

**Independent Test**: A credential-free receiver fixture proves the two product event shapes and flush lifecycle before merge; after the Owner supplies credentials and explicitly authorizes the existing release workflow, the Team Lead records the TestFlight build number and one read-only blob listing result.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** a macOS TestFlight build has valid approved Blob configuration, **when** the app completes startup or the user performs an approved key action, **then** the matching product event is admitted and a lifecycle flush attempts delivery to the configured existing container.
2. **US1/AC2** — **Given** product telemetry is enabled, **when** events are recorded, **then** the only product event types are `product.user_action` and `product.performance`, with closed action/operation labels and finite numeric duration values only.
3. **US1/AC3** — **Given** the shared adapter emits its owned operational heartbeat, **when** product-event inventory is assessed, **then** that documented content-free heartbeat is treated as adapter diagnostics rather than a third product event type.
4. **US1/AC4** — **Given** an accepted product event is pending, **when** startup completes, a recording/session ends, or the app resigns active, **then** a non-blocking flush is requested while pending files remain available for retry after failure or cancellation.
5. **US1/AC5** — **Given** the reviewed change is merged, the Owner has added both secrets, and the Owner explicitly authorizes the existing macOS release workflow, **when** that TestFlight build is used once, **then** the Team Lead can record the build number and blob name using a read-only listing without recording payload or credential contents.
6. **US1/AC6** — **Given** an approved event is scheduled from app-lifecycle or UI code, **when** the shared adapter performs synchronous admission and local persistence, **then** that work runs only through one serialized non-`@MainActor` lifecycle coordinator and the UI/lifecycle caller is not synchronously blocked by file I/O.

---

### User Story 2 - Fail closed around private content and missing configuration (Priority: P1)

As a VoxPocket user, my audio, live/final transcription, refined text, prompts, arbitrary error descriptions, and credentials never enter telemetry, and absent release configuration leaves the Blob path disabled without crashing or creating telemetry state.

**Why this priority**: Voice/text privacy and secret hygiene are constitutional red lines; a delivered event is unacceptable without mechanical proof of both.

**Independent Test**: Synthetic sentinel tests exercise every telemetry boundary with transcript, refined-text, audio, error, and credential markers, then prove zero sent or persisted marker bytes; a separate missing-configuration fixture proves disabled diagnostics, no identity request, no store creation, no network request, and no crash.

**Acceptance Scenarios**:

1. **US2/AC1** — **Given** a caller supplies an unknown event, key, label, free text, non-finite number, transcript marker, refined-text marker, audio marker, arbitrary error description, or credential marker, **when** the Blob admission boundary evaluates it, **then** the whole event is rejected before memory, disk, or network admission and the diagnostic contains no supplied value.
2. **US2/AC2** — **Given** existing Loki-producing code handles transcription or refinement failure, **when** it records telemetry, **then** it emits only reviewed closed categories or metrics and never an arbitrary localized/stringified error description or user content.
3. **US2/AC3** — **Given** either required Blob plist value is missing, empty, or unexpanded, **when** the standard host integration is constructed in Debug or Release, **then** it remains disabled without throwing, requesting identity, creating/opening its store, enqueueing, sending, or revealing a value.
4. **US2/AC4** — **Given** a Blob endpoint or SAS is present but invalid, **when** configuration is validated, **then** the app fails that Blob path closed with a fixed content-free diagnostic and keeps the rest of VoxPocket usable.
5. **US2/AC5** — **Given** repository, test, workflow, and log evidence, **when** secret hygiene is audited, **then** no endpoint/SAS value is committed, printed, interpolated into an error, copied into telemetry, or exposed in test fixtures.

---

### User Story 3 - Upgrade and release without regressing existing telemetry (Priority: P1)

As a maintainer, I can adopt the immutable shared-telemetry Blob API, preserve the existing Loki path, and detect release-plist or TestFlight-secret wiring drift before merge.

**Why this priority**: The Blob API is absent from the current dependency, and the release build is the only authorized place where real credentials may enter build settings.

**Independent Test**: Exact dependency-pin checks, existing package/app tests, privacy regressions, TestFlight packaging fixtures, and a synthetic Release build prove the selected shared-telemetry revision, unchanged Loki construction/flush behavior, expanded plist keys, and secret-only release injection.

**Acceptance Scenarios**:

1. **US3/AC1** — **Given** the `v0.2.0` release tag is absent, **when** dependency adoption is frozen, **then** every consumer uses the same full reviewed revision containing the Blob API; if the immutable tag exists before implementation publication, every consumer instead uses exact `0.2.0` and records its resolved revision.
2. **US3/AC2** — **Given** the new Blob path exists, **when** existing application use cases and local log collection run, **then** their Loki endpoint/token selection, store, event routing, log-sink filtering, and session-end flush behavior remain unchanged except for the privacy-authorized removal of arbitrary error text.
3. **US3/AC3** — **Given** a synthetic Release build, **when** its processed app plist is inspected, **then** both Blob keys are present, fully expanded from the required build settings, contain only synthetic values, and contain no unresolved build reference.
4. **US3/AC4** — **Given** an authorized macOS TestFlight run, **when** the archive starts, **then** both real values come only from GitHub Actions secrets at build time, are validated as present without value disclosure, and are unavailable to pull-request or local credential-free paths.
5. **US3/AC5** — **Given** the implementation changes dependency pins, CI/release configuration, or other CODEOWNERS paths, **when** the PR is delivered, **then** it is non-Draft, labeled/routed as important, lists the two Owner actions and exact commands, and waits for Owner approval without bypass.

### Edge Cases

- Only one of the two Blob settings is present, or a setting still contains `$(...)`.
- The endpoint is non-HTTPS, the SAS has broader than create/write intent, metadata is not allowlisted, or the store is already leased by another instance.
- An event has a safe name but an unknown key, unsafe label, non-finite duration, or sensitive sentinel embedded in an otherwise plausible field.
- The app is terminated or disabled during a flush; no unconfirmed file may be erased and no next request may start on the cancelled generation.
- Several UI/lifecycle signals arrive while admission or flush is active; the coordinator preserves admission order, joins rather than duplicates the active flush, and performs no synchronous file I/O on `@MainActor`.
- The dependency tag appears after planning but before the implementation candidate is published.
- A Release build is produced without real secrets for CI proof; it must use synthetic values and never contact Azure.
- The Owner has not added secrets or has not explicitly authorized a TestFlight run; implementation may be merged, but production delivery evidence remains pending.
- A rollback encounters pending Blob catalog, queue, sidecar, or capacity-ledger files; they must be retained rather than opened by the older adapter or deleted.

## Requirements

### Functional Requirements

- **FR-001**: VoxPocket MUST use one immutable shared-telemetry selection containing the public Azure Blob adapter across every Swift consumer manifest and dependency guard.
- **FR-002**: The existing Loki event service and local Loki log sink MUST remain separate from the Blob service; legacy events MUST NOT be fanned out to Blob implicitly.
- **FR-003**: The Blob service MUST use one dedicated Blob-only application-support store with one live owner and MUST NOT reuse, migrate, or delete Loki queue/log files.
- **FR-004**: Trusted app, build, and version metadata MUST be allowlisted from the built application; install identity MUST be a non-personal UUID supplied only for initial creation/reset.
- **FR-005**: The product event vocabulary MUST contain exactly `product.user_action` and `product.performance`; allowed keys and closed labels are defined in the telemetry contract, and no generic free-text property is allowed.
- **FR-006**: The SDK-owned `telemetry.heartbeat` MAY carry only its documented content-free operational fields and MUST NOT be emitted by product callers.
- **FR-007**: Blob admission MUST reject an entire event before accepted memory/storage/network state when its name, key, label, number, timestamp, or provenance violates the allowlist.
- **FR-008**: Audio, live/final transcripts, refined text, prompts, arbitrary error descriptions, credentials, endpoints, SAS values, and other user-derived text MUST never enter either Blob or Loki telemetry payloads.
- **FR-009**: Existing arbitrary error-description/reason telemetry fields MUST be replaced with closed content-free categories or removed, with sentinel regressions for the affected application and infrastructure boundaries.
- **FR-010**: Missing, empty, or unexpanded Blob configuration MUST use the adapter's disabled default without crash, identity provisioning, store access, enqueue, or network activity.
- **FR-011**: Present but invalid Blob configuration MUST fail only the Blob path closed, with fixed content-free diagnostics and no fallback receiver.
- **FR-012**: The app MUST retain one Blob service for the app lifetime and request non-blocking flushes after startup telemetry, at recording/session end, and when macOS resigns active; failed/cancelled work remains retryable.
- **FR-013**: The source plist MUST contain `LokiKitBlobEndpoint = $(TELEMETRY_BLOB_ENDPOINT)` and `LokiKitBlobSAS = $(TELEMETRY_BLOB_SAS)`, and both build settings MUST be required for an enabled Release transport.
- **FR-014**: Real Blob endpoint and SAS values MUST come only from GitHub Actions secrets during the authorized macOS TestFlight archive; no real value may be committed, logged, attached, or used by pull-request tests.
- **FR-015**: Credential-free tests MUST cover disabled-without-configuration, exact privacy allowlists, two product event shapes, no transcription/refined/audio/error/credential sentinel persistence or transport, flush lifecycle, and unchanged Loki behavior.
- **FR-016**: A required CI path MUST build a Release app with synthetic settings and inspect the processed plist for exact expansion; the test MUST NOT sign, upload, or contact a live telemetry receiver.
- **FR-017**: Existing Debug/local development, macOS manual TestFlight trigger semantics, iOS development builds, iOS TestFlight disablement, signing, build numbering, upload, and release-tag behavior MUST remain compatible.
- **FR-018**: The PR body MUST list the Owner's write-only SAS command and both GitHub secret-add commands exactly as accepted in MY-1818, but repository planning/source artifacts MUST use placeholders instead of real cloud resource identifiers.
- **FR-019**: No existing test, assertion, privacy gate, release guard, or policy may be removed, skipped, or weakened to deliver this feature.
- **FR-020**: After merge, Owner secret provisioning, and explicit release authorization, one used TestFlight build MUST produce a blob that the Team Lead verifies read-only by recording the build number and blob name only.
- **FR-021**: Every Blob admission, local-store mutation, and flush coordination operation MUST execute through one serialized non-`@MainActor` app-lifetime coordinator; `@MainActor` callers MAY only schedule asynchronous work and MUST NOT invoke the adapter's synchronous persistence API directly.

### Key Entities

- **Product Event**: One trusted event name with only allowlisted finite numeric values or closed labels; never user content.
- **Blob Configuration**: The two build-expanded host values plus trusted app/build/version metadata and explicit enablement state.
- **Blob Store**: The dedicated local queue/catalog/ledger owned by one adapter instance and retained across retry or rollback.
- **Delivery Evidence**: Non-sensitive build number, workflow/run reference, tested revision, and blob name; excludes payload and credentials.

## Existing Behaviour

- VoxPocket pins shared-telemetry `v0.1.0` at full revision `5f4b4d97d7ad05adb849e0d8937c8745d9b6d15f` in VoxInfrastructure, VoxApplication, and VoxPresentation; that release has no public Blob adapter.
- `ServiceContainer.makeTelemetryService()` constructs the legacy Loki service from `LOKI_ENDPOINT`/`LOKI_TOKEN`; Release falls back to `NoopTelemetryService` without the endpoint. Existing use cases receive that one service, and `endRecording()` requests its flush.
- `VoxPocketLogging` independently mirrors allowlisted local logs to Loki and owns a separate persisted log queue.
- No host plist/build setting, TestFlight secret, Blob-only store, or Blob lifecycle exists. The current required app build does not prove Release plist expansion.
- Existing telemetry records durations, counts, labels, and session IDs, but refinement and transcription failure paths also forward arbitrary localized/stringified errors. That conflicts with Constitution IV and the accepted privacy requirement.
- The release workflow is manual, checks out `main`, publishes macOS only, and injects App Store/signing secrets into Fastlane. iOS TestFlight remains disabled.

## Compatibility

- Loki endpoint/token selection, Noop fallback, local log mirroring, Loki store ownership, legacy safe event names/metrics, and existing flush timing remain in place; Blob is a second explicitly routed service.
- The public Swift module/product remains `LokiKit`; the upgrade is additive. All consumer manifests move together so SwiftPM never resolves mixed copies.
- Debug and credential-free Release builds remain usable with Blob disabled. iOS continues to compile/test but receives no newly authorized TestFlight release.
- No legacy queue is migrated. Rollback restores the prior dependency/config only after stopping the Blob owner and retaining all unconfirmed Blob files; reverting code does not retract transmitted events.
- Source/project/CI/dependency paths covered by CODEOWNERS remain important and require Owner approval. No admin merge, force push, or protection bypass is authorized.
- Real resource identifiers appear only in the Owner-command section of the PR body required by MY-1818, not in committed source, tests, fixtures, specs, or docs.

## Removed Behaviour

- **RB-001**: Remove arbitrary `error.localizedDescription` and stringified error/reason values from telemetry payloads; replace only with closed content-free categories where a failure distinction is needed. **Authority**: MY-1818 privacy requirement, FR-008/FR-009, and Constitution IV.
- **RB-002**: Do not route the existing legacy Loki event vocabulary into the Blob adapter; Blob accepts only the two product event types plus its SDK-owned heartbeat. **Authority**: MY-1818 “two base data types only,” FR-002/FR-005/FR-006.
- **RB-003**: Remove no Loki transport, safe metric, log sink, queue file, release guard, test, assertion, signing step, upload step, or platform restriction. Any such removal is outside this specification and requires a new decision.

## Scope Boundaries

### In scope

- Immutable shared-telemetry adoption in existing consumers and its repository dependency guard.
- A separate Blob-only app service, typed two-event product vocabulary, privacy policy, app-lifetime retention, dedicated store, and flush wiring.
- Privacy hardening and sentinel tests for current arbitrary error telemetry in VoxApplication and VoxInfrastructure.
- Host plist/build-setting wiring, synthetic Release expansion proof, TestFlight secret injection, credential-free packaging tests, and PR Owner-action instructions.
- Existing PR delivery followed by separately authorized post-merge TestFlight/read-only evidence.

### Non-goals

- Creating or changing Azure resources, generating a SAS, adding GitHub secrets, or listing blobs before the Owner acts.
- Sending transcripts, refined text, audio, prompts, error descriptions, credentials, or arbitrary strings for analytics.
- Replacing Loki, unifying Loki and Blob queues, migrating/deleting persisted telemetry, or modifying shared-telemetry itself.
- Enabling iOS TestFlight, automatic release triggers, background execution entitlements, exactly-once delivery, backend read access, or live Azure tests in CI.
- Adding consent UI, a telemetry settings page, new user identity/account linkage, or broader product analytics beyond the accepted two event types.
- Committing real endpoint, account, container, SAS, tenant, or other project-specific cloud identifiers.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Credential-free privacy tests admit only the two approved product event shapes and detect 100% of the supplied transcript, refined-text, audio, error, credential, unknown-key, unsafe-label, and non-finite sentinels before persistence or transport.
- **SC-002**: Missing-configuration tests observe zero crashes, identity-provider calls, store creations, enqueued events, and network requests in both Debug and Release fixtures.
- **SC-003**: Synthetic Release evidence finds both processed plist values fully expanded and zero real credential/resource values in repository or test output.
- **SC-004**: Existing Loki regression suites and all affected layer/repository gates finish with zero failures on the exact implementation candidate, with no removed or weakened test.
- **SC-005**: The important non-Draft PR receives Owner approval and all required checks pass on its exact head without bypass.
- **SC-006**: After Owner provisioning and explicit release authorization, one used macOS TestFlight build yields at least one blob; the evidence record contains exactly the build number, blob name, run/revision reference, and no payload or credential content.

## Assumptions

- The accepted Owner intent authorizes product telemetry for the macOS TestFlight build; no separate end-user consent UI is part of this version.
- At planning time `v0.2.0` is not published and reviewed shared-telemetry `main` is `0ffdbc82a5fbd76f54e49127b0d30a4fb8666e95`; the issue's tag-if-available rule remains binding at implementation publication.
- The adapter's documented create-only SAS validation, privacy allowlist, dedicated store lease, disabled missing-config behavior, heartbeat, and retry semantics are used without modification.
- GitHub Actions masking is defense in depth, not permission to interpolate or print a secret; production build wiring passes secret names/references rather than values through logged configuration.
- The existing manual macOS TestFlight workflow remains the only release path and requires an explicit Owner request even after secrets are provisioned.
