# Feature Specification: Portable macOS TestFlight signing

**Feature Branch**: `011-macos-testflight-profile`

**Created**: 2026-10-15

**Status**: Draft

**Input**: MY-1768 revision 4 and Team Lead repair handoff on VoxPocket `main` at `20f9c36e9c60e2c2dcee2514d83138826caa91f6`

## User Scenarios & Testing

### User Story 1 - Release with the profile fetched in this run (Priority: P1)

As the release operator, I can start the existing manual macOS TestFlight release and have the archive and export use the matching App Store profile fetched or created during that same run, without relying on a display name from an earlier machine.

**Why this priority**: The current fixed profile-name dependency prevents VoxPocket from producing a macOS TestFlight build on the release runner.

**Independent Test**: Credential-free regression evidence proves that the profile fetched for the VoxPocket macOS app is the one supplied to both archive and export, and that a missing profile name stops before any archive or upload.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** the existing App Store Connect key can access the VoxPocket app, **when** the operator starts the authorized macOS release, **then** the run fetches or creates and installs a matching macOS App Store profile before archive.
2. **US1/AC2** — **Given** that fetch publishes a non-empty canonical profile name, **when** the archive and export are configured, **then** both use that exact current-run name and no fixed profile display name.
3. **US1/AC3** — **Given** the canonical name is missing or empty, **when** the lane reaches signing preparation, **then** it fails before archive without printing profile or credential contents.
4. **US1/AC4** — **Given** the runner already has the required Apple Distribution and Mac Installer Distribution private keys, **when** the change runs, **then** it uses those existing identities without adding, replacing, or reconfiguring host keychains.
5. **US1/AC5** — **Given** a profile name contains spaces or shell metacharacters, **when** it crosses the archive boundary, **then** it remains one opaque target-specific value.

---

### User Story 2 - Detect signing drift before a release (Priority: P1)

As a maintainer, I receive deterministic pull-request evidence when the current-run profile handoff, manual-only release guard, platform selection, or installer-signing portability contract drifts.

**Why this priority**: The incident must become a mechanical guard that runs without Apple credentials or a real upload.

**Independent Test**: The repository's existing automatic Python and Ruby test discovery executes red-capable signing regressions, while the local policy and app-layer gates pass without signing or uploading an app.

**Acceptance Scenarios**:

1. **US2/AC1** — **Given** the historical fixed-name configuration, **when** the new regression is evaluated, **then** it fails.
2. **US2/AC2** — **Given** the repaired configuration, **when** repository tests run, **then** they prove current-run profile reuse, fail-closed behavior, opaque transport, target mapping, and the absence of a personal certificate subject.
3. **US2/AC3** — **Given** the existing manual release workflow, **when** the repair is applied, **then** manual dispatch, `main` checkout, macOS-only selection, no-new-commit gating, non-cancelling uploads, build-number behavior, and upload behavior remain unchanged.
4. **US2/AC4** — **Given** no Apple credentials or profiles are present, **when** local verification runs, **then** the static/fixture tests and unsigned app build path remain usable.

---

### User Story 3 - Record the production proof under Owner control (Priority: P1)

As the Owner, after the reviewed change reaches `main`, I can explicitly authorize one manual macOS TestFlight run and receive the run URL, exact `main` SHA, successful build number, and terminal upload result.

**Why this priority**: Only a real, explicitly authorized release can prove the repaired path against App Store Connect and the self-hosted runner.

**Independent Test**: After merge and explicit Owner authorization, one manual run on `main` reaches successful upload/processing and records non-sensitive evidence.

**Acceptance Scenarios**:

1. **US3/AC1** — **Given** the reviewed implementation is merged and the Owner explicitly authorizes the run, **when** the existing macOS workflow is manually dispatched on `main`, **then** it completes the macOS archive, package export, and TestFlight upload.
2. **US3/AC2** — **Given** the run completes, **when** evidence is recorded, **then** it includes the run URL, exact head SHA, build number, and terminal conclusion without profile, key, certificate, or keychain contents.
3. **US3/AC3** — **Given** merge or explicit authorization is absent, **when** implementation verification finishes, **then** no agent dispatches the release workflow or claims production success.

### Edge Cases

- App Store Connect has no reusable profile and the release action must create one.
- The fetched profile is stale for the current certificate or capabilities and must be refreshed.
- The canonical profile-name output is missing, blank, or contains whitespace and shell metacharacters.
- The archive and export mappings accidentally use different profile sources.
- The Mac Installer Distribution certificate selector resolves no existing valid identity; the run must fail without mutating the keychain.
- A code change accidentally enables iOS TestFlight or changes the manual/no-new-commit/concurrency guard.
- A post-review content change invalidates the reviewed candidate and its evidence.

## Requirements

### Functional Requirements

- **FR-001**: The macOS release MUST fetch or create and install the VoxPocket App Store provisioning profile during the authorized release run using the existing App Store Connect authentication.
- **FR-002**: The archive and export MUST consume the same non-empty canonical profile name produced by FR-001.
- **FR-003**: The system MUST NOT rely on a fixed macOS provisioning-profile display name or a fallback source that can differ from the canonical current-run name.
- **FR-004**: A missing or empty canonical profile name MUST fail before archive and MUST NOT disclose profile values or credential material.
- **FR-005**: The current-run profile name MUST cross the archive boundary as one opaque macOS-target-specific value.
- **FR-006**: Release signing MUST remain Manual with Apple Distribution for the app and a team-agnostic Mac Installer Distribution selector for package export; no personal account name may be committed.
- **FR-007**: The repair MUST use only the existing `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, and `KEYCHAIN_PASSWORD` secrets and MUST NOT modify host keychain state beyond the existing unlock/access preparation.
- **FR-008**: The workflow MUST remain explicit manual dispatch on `main`, macOS-only, non-cancelling, and guarded against redundant releases unless forced; iOS TestFlight MUST remain disabled.
- **FR-009**: Build-number selection, `.pkg` validation, upload/processing behavior, and release-tag movement MUST remain unchanged.
- **FR-010**: Credential-free regressions MUST fail on both the historical fixed-name state and the current fabricated environment-key consumer, and cover profile acquisition through the real Fastlane class contract, canonical-name validation, archive/export reuse, shell-safe transport, project signing configuration, installer selector portability, and preserved workflow guards.
- **FR-011**: The generated Xcode project already repaired on the current baseline MUST remain synchronized from its declared source of truth and compatible with unsigned local/CI builds; this repair MUST NOT mutate it.
- **FR-012**: The implementation MUST pass the repository's existing policy, app-layer, and complete verification contracts without deleting, skipping, or weakening a test.
- **FR-013**: A real TestFlight run MUST occur only after reviewed merge and explicit Owner authorization, and its non-sensitive run URL, head SHA, build number, and terminal result MUST be recorded.

## Existing Behaviour

- The release is a manual, macOS-only workflow that checks out `main`, unlocks the existing login keychain, runs credential-free packaging tests, and invokes the macOS Fastlane lane.
- Release signing is Manual with Apple Distribution. The current app project accepts the runtime macOS profile input, but the lane reads a fabricated per-app environment key instead of Fastlane 2.241.0's `SharedValues::SIGH_NAME` lane-context output; run `38678678083` therefore stopped before archive even though acquisition produced `SIGH_NAME`.
- The lane already authenticates with the existing App Store Connect API key, exports a `.pkg`, validates that artifact, uploads it as platform `osx`, waits for processing, and advances the macOS release tag.
- The lane already uses the portable `Mac Installer Distribution` selector and the repository contains no committed personal installer subject in this path.
- Existing tests cover package routing, macOS upload, build-number selection, invalid artifacts, iOS pause, manual workflow guards, widget platform separation, and current-run reuse, but they stub the profile action and reproduce the same invalid environment-key assumption instead of exercising the real Fastlane producer class.

## Compatibility

- Manual trigger semantics, `main` checkout, macOS-only authorization, concurrency, force/no-new-commit behavior, build numbering, `.pkg` validation, upload behavior, and release-tag behavior are preserved.
- iOS TestFlight remains disabled and its existing profile settings are not migrated by this version.
- Existing secret names and the runner's installed signing private keys are reused. No new secret, profile file, keychain entry, certificate import, or host setup step is introduced.
- Unsigned local and CI builds remain credential-free; no local archive, signing, upload, or app installation is permitted.
- The repair is an important PR because it touches the CODEOWNERS-protected Fastlane release surface; Owner approval remains mandatory.

## Removed Behaviour

- **RB-001**: Preserve the accepted removal of archive-time and export-time dependence on the fixed macOS profile display name. **Authority**: MY-1768 Goal and US1/AC2.
- **RB-002**: Remove the fabricated per-app environment-key consumer and continue to forbid fallback to the provisioning action return value when the canonical current-run profile name is missing. **Authority**: FR-002 through FR-004 and incident fail-closed requirements.
- **RB-003**: Preserve the accepted absence of the committed personal installer certificate subject and retain the already-landed team-agnostic `Mac Installer Distribution` selector unchanged. **Authority**: repository agent protocol §8 and FR-006.
- **RB-004**: Remove no test, assertion, workflow gate, release guard, secret validation, upload step, or platform restriction. Any such removal is outside this specification and requires a new decision.

## Scope Boundaries

### In scope

- The macOS provisioning-profile handoff from the real Fastlane 2.241.0 action output through archive and export.
- Credential-free regression repair through existing repository discovery and gates, including the real Fastlane action class boundary.
- Read-only verification that the accepted XcodeGen, workflow, installer-selector, documentation, and release-orchestration behavior remains unchanged.
- Reviewed non-Draft PR delivery and the separately Owner-controlled production validation.

### Non-goals

- Enabling or changing iOS TestFlight delivery.
- Changing bundle identifiers, entitlements, app capabilities, marketing version, build-number policy, upload/distribution policy, release-tag behavior, or user-facing app behavior.
- Adding secrets, importing/replacing certificates, creating a new keychain, or changing runner configuration.
- Dispatching a real release before reviewed merge and explicit Owner authorization.
- Modifying Developer Portal profiles or certificates outside the lane's existing fetch/create behavior.
- Editing `VoxPocket/project.yml`, the generated Xcode project, `.github/workflows/testflight.yml`, release documentation, or any product source in this repair.
- Repairing the pre-existing unpinned AppleUITesting checkout in the release workflow.
- Copying VitalStride implementation details or treating VitalStride #441 as authority for VoxPocket.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Credential-free regression evidence detects the historical fixed-name state and the current fabricated environment-key consumer, and passes only when the real Fastlane action's one current-run macOS profile value drives both archive and export.
- **SC-002**: All repository planning and implementation verification commands required by the reviewed plan finish with zero failures on the exact candidate revision.
- **SC-003**: The implementation adds zero secrets and zero host keychain mutation steps, and no committed personal account name remains in the touched signing path.
- **SC-004**: The important non-Draft PR is approved by the Owner and all required checks are green on its exact head SHA.
- **SC-005**: After explicit Owner authorization, one manual macOS TestFlight run on merged `main` records a successful terminal result, run URL, exact head SHA, and build number.

## Assumptions

- Fastlane 2.241.0 continues to publish the canonical installed App Store profile name through its existing action lane-context output for the VoxPocket bundle identifier.
- The self-hosted runner retains valid Apple Distribution and Mac Installer Distribution private keys for team `4Z8GG667QD`; this feature does not provision or rotate them.
- A generic Mac Installer Distribution automatic selector is the repository-safe way to select the existing valid installer identity without committing a personal certificate subject.
- VitalStride PR #441 is comparative evidence for the incident class only; VoxPocket paths, one-target macOS topology, tests, and authority remain repository-specific.
- The Owner-controlled post-merge release may mutate Developer Portal profile state through the lane's existing fetch/create behavior and publish a build, so it remains an external authorization gate.
