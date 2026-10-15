# Feature Specification: Privacy-safe Azure Blob product telemetry

**Feature Branch**: `012-azure-blob-telemetry`

**Created**: 2026-10-15

**Status**: Ready for fresh spec-gate review

**Input**: MY-1818 issue revision 1, Team Lead planning handoff, and VoxPocket `main` at `9fddff22af2c9f693e0a90155b224a5fb41dbf06`

## User Scenarios & Testing

### User Story 1 - Observe a real TestFlight product event (Priority: P1)

As the product owner, I can explicitly enable “Send usage data”, use a configured macOS TestFlight build once, and find a privacy-approved product event in the existing telemetry container, so consented product usage is observable without creating another cloud resource.

**Why this priority**: The workflow outcome is one real product event delivered from VoxPocket; local or synthetic evidence alone does not complete it.

**Independent Test**: A credential-free receiver fixture proves the two product event shapes and flush lifecycle before merge; after the Owner supplies credentials and explicitly authorizes the existing release workflow, the tester separately opts in through Settings and performs an approved action, then the Team Lead records the TestFlight build number and one read-only blob listing result.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** a macOS TestFlight build has valid approved Blob configuration and the user has separately enabled “Send usage data”, **when** a later app startup completes or the user performs an approved key action, **then** the matching product event is admitted and a lifecycle flush attempts delivery to the configured existing container.
2. **US1/AC2** — **Given** product telemetry is enabled, **when** events are recorded, **then** the only product event types are `product.user_action` and `product.performance`, with closed action/operation labels and finite numeric duration values only.
3. **US1/AC3** — **Given** the shared adapter emits its owned operational heartbeat, **when** product-event inventory is assessed, **then** that documented content-free heartbeat is treated as adapter diagnostics rather than a third product event type.
4. **US1/AC4** — **Given** an accepted product event is pending, **when** startup completes, a recording/session ends, or the app resigns active, **then** a non-blocking flush is requested while pending files remain available for retry after failure or cancellation.
5. **US1/AC5** — **Given** the reviewed change is merged, the Owner has added both secrets, and the Owner explicitly authorizes the existing macOS release workflow, **when** the tester separately opts in through “Send usage data” and uses that TestFlight build for an approved action, **then** the Team Lead can record the build number and blob name using a read-only listing without recording payload or credential contents.
6. **US1/AC6** — **Given** the standard bundle initializer is used, **when** the host constructs the service, admits a product event through `track`, or requests `flush`, **then** those host calls run only through one serialized non-`@MainActor` lifecycle coordinator and no UI/lifecycle caller is synchronously blocked by file I/O; only the SDK-owned, internally synchronized, content-free startup/daily heartbeat is exempt from traversing the host coordinator.
7. **US1/AC7** — **Given** a new or existing installation has not explicitly enabled “Send usage data”, **when** VoxPocket starts, **then** the persisted setting defaults off and no Blob service is constructed, event is admitted, or upload is attempted; turning it off later immediately stops new admission and upload while retaining pending local files and any previously created install UUID, and a later explicit opt-in reuses that same UUID.
8. **US1/AC8** — **Given** no install identity exists, **when** the user opts in for the first time, **then** VoxPocket creates and persists one random non-personal install UUID; eligible app launches and later explicit opt-ins reuse that UUID for the app installation's lifetime, consent-off state never actively requests or uses it, and no Settings Reset or identity-rotation surface exists in v1.

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
6. **US2/AC6** — **Given** a CLI, headless helper, or test host, **when** its composition root starts, **then** it never constructs the Blob telemetry service regardless of configuration or persisted consent fixtures.

---

### User Story 3 - Upgrade and release without regressing existing telemetry (Priority: P1)

As a maintainer, I can adopt the immutable shared-telemetry Blob API, preserve the existing Loki path, and detect release-plist or TestFlight-secret wiring drift before merge.

**Why this priority**: The Blob API is absent from the current dependency, and the release build is the only authorized place where real credentials may enter build settings.

**Independent Test**: Exact dependency-version and annotated-tag integrity checks, existing package/app tests, privacy regressions, TestFlight packaging fixtures, and a synthetic Release build prove shared-telemetry exact `0.2.0`, unchanged Loki construction/flush behavior, expanded plist keys, and secret-only release injection.

**Acceptance Scenarios**:

1. **US3/AC1** — **Given** annotated tag `v0.2.0` is verified to peel to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, **when** dependency adoption is frozen, **then** every consumer, guard, current authority, and current projection uses SwiftPM `exact: "0.2.0"`; the tag object and peeled commit are recorded only as integrity evidence, and no branch or revision selector is an allowed fallback.
2. **US3/AC2** — **Given** the new Blob path exists, **when** existing application use cases and local log collection run, **then** their Loki endpoint/token selection, store, event routing, log-sink filtering, and session-end flush behavior remain unchanged except for the privacy-authorized removal of arbitrary error text.
3. **US3/AC3** — **Given** a synthetic Release build, **when** its processed app plist is inspected, **then** both Blob keys are present, fully expanded from the required build settings, contain only synthetic values, and contain no unresolved build reference.
4. **US3/AC4** — **Given** an authorized macOS TestFlight run, **when** the archive starts, **then** CI writes both real GitHub Actions secret values to one untracked runner-temp xcconfig with mode `0600`, passes only that file's path through `-xcconfig`, deletes it in an `always`/`ensure` path, and exposes neither raw nor escaped sentinel/value forms in Release logs, xcargs, command-line environment assignments, or other printable arguments.
5. **US3/AC5** — **Given** the implementation is split into dependency, privacy, app-runtime, app-adoption, synthetic-Release, and TestFlight-injection changes, **when** each single-goal PR is delivered, **then** it independently leaves `main` working, is non-Draft, carries its own exact-SHA verification/review/publication evidence, and waits for applicable CODEOWNERS/Owner approval without bypass; PR01, PR02, and PR03 each depend directly on PR00 and may run concurrently, PR04 waits for all three, and only the TestFlight-injection PR lists the exact Owner provisioning and secret commands.

### Edge Cases

- Only one of the two Blob settings is present, or a setting still contains `$(...)`.
- The endpoint is non-HTTPS; the SAS is a user-delegation token, contains an unsupported query name, has `sr` other than `c`, or has an explicit `sp` other than `c`; the stored-policy token lacks `si`/`sig`; metadata is not allowlisted; or the store is already leased by another instance.
- An event has a safe name but an unknown key, unsafe label, non-finite duration, or sensitive sentinel embedded in an otherwise plausible field.
- The app is terminated or disabled during a flush; no unconfirmed file may be erased and no next request may start on the cancelled generation.
- Consent is disabled while admission or upload is active; the coordinator stops the active generation, admits no later event, retains unconfirmed files, and does not resume until a later explicit opt-in.
- A first opt-in races with repeated Settings toggle actions or eligible launches; exactly one random UUID is persisted for the app installation's lifetime, consent-off work admits or uploads nothing, and later explicit opt-in reuses that same UUID.
- Several UI/lifecycle signals arrive while admission or flush is active; the host coordinator preserves admission order, joins rather than duplicates the active flush, and performs no synchronous file I/O on `@MainActor`. SDK-owned heartbeat ticks remain internally synchronized and off-main without becoming a host/product event bypass.
- The `v0.2.0` tag is missing, moved, no longer annotated, or no longer peels to the reviewed commit; PR01 blocks and escalates instead of falling back to a revision selector.
- A Release build is produced without real secrets for CI proof; it must use synthetic values and never contact Azure.
- The Owner has not added secrets or has not explicitly authorized a TestFlight run; implementation may be merged, but production delivery evidence remains pending.
- A rollback encounters pending Blob catalog, queue, sidecar, or capacity-ledger files; they must be retained rather than opened by the older adapter or deleted.

## Requirements

### Functional Requirements

- **FR-001**: VoxPocket MUST use SwiftPM `exact: "0.2.0"` for shared-telemetry across every Swift consumer manifest, dependency guard, current authority, and current projection. A branch, revision selector, or revision fallback is forbidden; the annotated tag object and its peeled commit are integrity evidence only. The protected constitution change MUST be a deliberate amendment naming the rule, reason, and migration impact; historical baseline evidence remains explicitly historical.
- **FR-002**: The existing Loki event service and local Loki log sink MUST remain separate from the Blob service; legacy events MUST NOT be fanned out to Blob implicitly.
- **FR-003**: The Blob service MUST use one dedicated Blob-only application-support store with one live owner and MUST NOT reuse, migrate, or delete Loki queue/log files.
- **FR-004**: Trusted app, build, and version metadata MUST be allowlisted from the built application; install identity MUST be a non-personal UUID created only on first explicit opt-in, persisted locally, and reused for the app installation's lifetime.
- **FR-005**: The product event vocabulary MUST contain exactly `product.user_action` and `product.performance`; allowed keys and closed labels are defined in the telemetry contract, and no generic free-text property is allowed.
- **FR-006**: The SDK-owned `telemetry.heartbeat` MAY carry only its documented content-free operational fields and MUST NOT be emitted by product callers. Decision 2A exempts only the initializer-owned, internally synchronized, off-main startup/daily heartbeat from the host coordinator; it does not permit a second host/store owner, a product `track` bypass, or main-thread synchronous persistence.
- **FR-007**: Blob admission MUST reject an entire event before accepted memory/storage/network state when its name, key, label, number, timestamp, or provenance violates the allowlist.
- **FR-008**: Audio, live/final transcripts, refined text, prompts, arbitrary error descriptions, credentials, endpoints, SAS values, and other user-derived text MUST never enter either Blob or Loki telemetry payloads.
- **FR-009**: Existing arbitrary error-description/reason telemetry fields MUST be replaced with closed content-free categories or removed, with sentinel regressions for the affected application and infrastructure boundaries.
- **FR-010**: Missing, empty, or unexpanded Blob configuration MUST use the adapter's disabled default without crash, identity provisioning, store access, enqueue, or network activity.
- **FR-011**: Present but invalid Blob configuration MUST fail only the Blob path closed, with fixed content-free diagnostics and no fallback receiver.
- **FR-012**: The interactive app MUST have at most one live Blob service/coordinator generation while consent is on and request non-blocking flushes after startup telemetry, at recording/session end, and when macOS resigns active; disabling, failed, or cancelled work remains retryable.
- **FR-013**: The source plist MUST contain `LokiKitBlobEndpoint = $(TELEMETRY_BLOB_ENDPOINT)` and `LokiKitBlobSAS = $(TELEMETRY_BLOB_SAS)`, and both build settings MUST be required for an enabled Release transport.
- **FR-014**: Real Blob endpoint and SAS values MUST come only from GitHub Actions secrets during the authorized macOS TestFlight archive. CI MUST write them to one untracked runner-temp xcconfig with mode `0600`, pass only its path via `-xcconfig`, and delete it in an `always`/`ensure` path; values MUST NOT appear in source, attachments, xcargs, command-line environment assignments, printable arguments, or logs.
- **FR-015**: Credential-free tests MUST cover disabled-without-configuration, exact privacy allowlists, the two product event shapes, SDK-owned heartbeat ownership, coordinator-only host construction/`track`/`flush`, stored-policy SAS query compatibility, no transcription/refined/audio/error/credential sentinel persistence or transport, flush lifecycle, and unchanged Loki behavior.
- **FR-016**: A required CI path MUST build a Release app with synthetic settings and inspect the processed plist for exact expansion; TestFlight packaging tests MUST prove both raw and shell/percent-escaped synthetic sentinel forms are absent from Release-path logs. Neither path may sign, upload, contact a live telemetry receiver, or expose a value-bearing argument.
- **FR-017**: Existing Debug/local development, macOS manual TestFlight trigger semantics, iOS development builds, iOS TestFlight disablement, signing, build numbering, upload, and release-tag behavior MUST remain compatible.
- **FR-018**: The TestFlight-injection PR body MUST list the exact Owner-only Decision 1A commands: create a stored access policy with key-based auth, permission `c`, and explicit UTC expiry; generate an HTTPS-only container service SAS with `--policy-name` and key-based auth; and set both GitHub Actions secrets. Committed artifacts MUST use placeholders instead of real cloud identifiers. The stored-policy token MUST use only supported query names with `sr=c`, non-empty `si`/`sig`, optional `sv`, and `spr=https`; policy authorization means explicit `sp` is normally absent, while any explicit `sp` MUST equal `c`. User-delegation fields and `--as-user` are forbidden, and agents MUST NOT execute, inspect, or persist the real token.
- **FR-019**: No existing test, assertion, privacy gate, release guard, or policy may be removed, skipped, or weakened to deliver this feature.
- **FR-020**: After merge, Owner secret provisioning, explicit release authorization, and a separate tester opt-in through “Send usage data”, one approved action in the TestFlight build MUST produce a blob that the Team Lead verifies read-only by recording the build number and blob name only. Owner release authorization MUST NOT be treated as end-user consent.
- **FR-021**: The exact `AzureBlobTelemetryService(bundle:app:build:version:privacy:storeDirectory:isEnabled:identityProvider:configuration:maxDiskBytes:)` construction plus every host product `track` and lifecycle `flush` call MUST execute through one serialized non-`@MainActor` app-lifetime coordinator; `@MainActor` callers MAY only schedule asynchronous work. Decision 2A exempts only SDK-owned, internally synchronized, off-main heartbeat work performed after that construction.
- **FR-022**: Settings MUST expose a persisted `UserDefaults` opt-in named “Send usage data” that defaults off. Turning it off MUST immediately stop Blob admission and upload while retaining pending local files under SDK disable semantics; re-enablement MUST require a fresh explicit opt-in before either resumes.
- **FR-023**: First opt-in MUST create and locally persist one random UUID; disable MUST retain it without active-service identity request/use, and every later explicit opt-in and eligible app launch MUST reuse that same UUID for the app installation's lifetime. V1 MUST expose no install-ID Reset or rotation surface, require no shared-telemetry API change, and perform no host parsing of adapter-private storage or catalog state. The UUID MUST NOT appear in product properties, diagnostics, or evidence.
- **FR-024**: CLI, headless, and test hosts MUST never construct the Blob telemetry service. Only the interactive app composition root MAY construct it after valid configuration and persisted consent are both present.

### Key Entities

- **Product Event**: One trusted event name with only allowlisted finite numeric values or closed labels; never user content.
- **Blob Configuration**: The two build-expanded host values plus trusted app/build/version metadata and explicit enablement state.
- **Blob Store**: The dedicated local queue/catalog/ledger owned by one adapter instance and retained across retry or rollback.
- **Product Telemetry Consent**: A persisted `UserDefaults` boolean, default off, changed only through the “Send usage data” Settings control and consumed at the app composition boundary.
- **Install Identity**: A random non-personal UUID absent until first opt-in, retained but inactive across disable, and reused after every later opt-in and eligible launch for the app installation's lifetime.
- **Delivery Evidence**: Non-sensitive build number, workflow/run reference, tested revision, and blob name; excludes payload and credentials.

## Existing Behaviour

- VoxPocket pins shared-telemetry `v0.1.0` at full revision `5f4b4d97d7ad05adb849e0d8937c8745d9b6d15f` in VoxInfrastructure, VoxApplication, and VoxPresentation; that release has no public Blob adapter.
- `ServiceContainer.makeTelemetryService()` constructs the legacy Loki service from `LOKI_ENDPOINT`/`LOKI_TOKEN`; Release falls back to `NoopTelemetryService` without the endpoint. Existing use cases receive that one service, and `endRecording()` requests its flush.
- `VoxPocketLogging` independently mirrors allowlisted local logs to Loki and owns a separate persisted log queue.
- No host plist/build setting, TestFlight secret, Blob-only store, or Blob lifecycle exists. The current required app build does not prove Release plist expansion.
- No product-telemetry consent preference, “Send usage data” Settings control, or persisted install UUID exists.
- Existing telemetry records durations, counts, labels, and session IDs, but refinement and transcription failure paths also forward arbitrary localized/stringified errors. That conflicts with Constitution IV and the accepted privacy requirement.
- The release workflow is manual, checks out `main`, publishes macOS only, and injects App Store/signing secrets into Fastlane. iOS TestFlight remains disabled.

## Compatibility

- Loki endpoint/token selection, Noop fallback, local log mirroring, Loki store ownership, legacy safe event names/metrics, and existing flush timing remain in place; Blob is a second explicitly routed service.
- The public Swift module/product remains `LokiKit`; the upgrade is additive. All consumer manifests move together to exact `0.2.0` so SwiftPM never resolves mixed copies.
- Debug and credential-free Release builds remain usable with Blob disabled. iOS continues to compile/test but receives no newly authorized TestFlight release.
- Existing Settings pages and preferences remain; one default-off product-telemetry section is additive. CLI, headless, and test hosts retain zero Blob construction.
- No legacy queue is migrated. Rollback restores the prior dependency/config only after stopping the Blob owner and retaining all unconfirmed Blob files; reverting code does not retract transmitted events.
- Source/project/CI/dependency paths covered by CODEOWNERS remain important and require Owner approval in their own single-goal PRs. No admin merge, force push, or protection bypass is authorized, and no review/check evidence is reused across PR heads.
- Real resource identifiers appear only in the Owner-command section of the PR body required by MY-1818, not in committed source, tests, fixtures, specs, or docs.

## Removed Behaviour

- **RB-001**: Remove arbitrary `error.localizedDescription` and stringified error/reason values from telemetry payloads; replace only with closed content-free categories where a failure distinction is needed. **Authority**: MY-1818 privacy requirement, FR-008/FR-009, and Constitution IV.
- **RB-002**: Do not route the existing legacy Loki event vocabulary into the Blob adapter; Blob accepts only the two product event types plus its SDK-owned heartbeat. **Authority**: MY-1818 “two base data types only,” FR-002/FR-005/FR-006.
- **RB-003**: Remove no Loki transport, safe metric, log sink, queue file, release guard, test, assertion, signing step, upload step, or platform restriction. Any such removal is outside this specification and requires a new decision.

## Scope Boundaries

### In scope

- Immutable shared-telemetry adoption in existing consumers and its repository dependency guard.
- A separate Blob-only app service, typed two-event product vocabulary, privacy policy, app-lifetime retention, dedicated store, and flush wiring.
- A persisted default-off “Send usage data” Settings opt-in, immediate disable/re-enable semantics, first-opt-in install identity with app-lifetime reuse, and zero-construction exclusions for CLI/headless/test hosts.
- Privacy hardening and sentinel tests for current arbitrary error telemetry in VoxApplication and VoxInfrastructure.
- Host plist/build-setting wiring, synthetic Release expansion proof, temporary-`0600`-xcconfig TestFlight secret injection, raw/escaped log-absence tests, credential-free packaging tests, and exact placeholder-only Owner-action instructions.
- Existing PR delivery followed by separately authorized post-merge TestFlight/read-only evidence.

### Non-goals

- Creating or changing Azure resources, generating a SAS, adding GitHub secrets, or listing blobs before the Owner acts.
- Sending transcripts, refined text, audio, prompts, error descriptions, credentials, or arbitrary strings for analytics.
- Replacing Loki, unifying Loki and Blob queues, migrating/deleting persisted telemetry, or modifying shared-telemetry itself.
- Enabling iOS TestFlight, automatic release triggers, background execution entitlements, exactly-once delivery, backend read access, or live Azure tests in CI.
- Adding user/account linkage, identity derived from personal/device/account data, or broader product analytics beyond the accepted two event types.
- Committing real endpoint, account, container, SAS, tenant, or other project-specific cloud identifiers.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Credential-free privacy tests admit only the two approved product event shapes and detect 100% of the supplied transcript, refined-text, audio, error, credential, unknown-key, unsafe-label, and non-finite sentinels before persistence or transport.
- **SC-002**: Missing-configuration tests observe zero crashes, identity-provider calls, store creations, enqueued events, and network requests in both Debug and Release fixtures.
- **SC-003**: Synthetic Release evidence finds both processed plist values fully expanded, and TestFlight packaging evidence finds zero raw or escaped sentinel forms and zero real credential/resource values in repository, arguments, or Release-path logs.
- **SC-004**: Existing Loki regression suites and all affected layer/repository gates finish with zero failures on the exact implementation candidate, with no removed or weakened test.
- **SC-005**: Every implementation PR independently leaves `main` working, receives applicable Owner approval, and passes its focused verification plus `scripts/verify` and required checks on its own exact head without bypass.
- **SC-006**: After Owner provisioning, explicit release authorization, and a separate tester Settings opt-in, one approved action in the macOS TestFlight build yields at least one blob; the evidence record contains exactly the build number, blob name, run/revision reference, and no payload or credential content.
- **SC-007**: Consent/identity/host-composition tests prove default-off persistence; zero service/store/admission/upload and zero identity creation/provider request before first opt-in; no active-service identity request/use while off; retained pending files and the persisted UUID across disable; reuse of that same UUID after every later explicit opt-in and eligible app launch for the app installation's lifetime; no v1 Reset/rotation surface; and zero Blob-service construction in every CLI/headless/test host fixture.

## Assumptions

- The MY-1841 common consent contract is binding for this product telemetry: the macOS app exposes the persisted default-off Settings opt-in, one random first-opt-in UUID is reused for the app installation's lifetime, v1 exposes no install-ID Reset, and excluded non-interactive hosts never construct the service. Any future Reset is a separate shared-telemetry SDK feature and is outside this scope.
- The original planning snapshot predated `v0.2.0` publication. That dependency-selection assumption is superseded: annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` now peels to reviewed commit `903f4b9bc01cfcfeba3ce96e13519d841781b40a`, and the binding selector is exact `0.2.0` with no revision fallback.
- Decision 1A selects an Owner-created, key-authenticated stored access policy with permission `c` and explicit expiry, then an HTTPS-only container service SAS bound by `si`; the policy form omits `sp`, and the provider rule remains “if `sp` is present, it is exactly `c`.”
- Decision 2A selects the exact bundle initializer and narrowly exempts only its SDK-owned, internally synchronized, content-free off-main heartbeat from the host coordinator.
- GitHub Actions masking is defense in depth, not permission to interpolate or print a secret; production build wiring passes only a runner-temp xcconfig path through printable archive arguments and proves raw/escaped sentinel absence.
- The existing manual macOS TestFlight workflow remains the only release path and requires an explicit Owner request even after secrets are provisioned.
