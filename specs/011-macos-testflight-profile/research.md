# Research: Portable macOS TestFlight signing

## Evidence

- Planning base and `origin/main`: `20f9c36e9c60e2c2dcee2514d83138826caa91f6`.
- Historical manual run `38598643529` failed because the old fixed macOS profile display name was unavailable; the accepted repair removed that fixed-name dependency.
- Post-merge manual run `38678678083` on `main` `20f9c36e9c60e2c2dcee2514d83138826caa91f6` successfully produced Fastlane's `SIGH_NAME`, but the lane read `ENV["sigh_#{APP_IDENTIFIER}_appstore_profile-name"]`; the fail-closed guard therefore stopped before archive.
- `VoxPocket/project.yml` now carries the accepted target-specific macOS Release profile input while preserving base signing Automatic and Release Manual + Apple Distribution.
- `fastlane/Fastfile` force-refreshes and installs the macOS profile, but consumes a fabricated environment key rather than Fastlane 2.241.0's lane-context shared value. Archive therefore receives no current-run macOS profile variable.
- The mac lane already uses the existing App Store Connect API key, platform `macos` profile acquisition, platform `osx` build numbering/upload, `.pkg` validation, and the existing runner keychain.
- `fastlane/Fastfile` already uses the accepted generic `Mac Installer Distribution` selector; that selector and all certificate/keychain behavior are read-only in this repair.
- `scripts/tests/test_testflight_packaging.rb` stubs the `GetProvisioningProfileAction` itself and fabricates the same invalid environment key, so it cannot detect drift from the real Fastlane class contract.
- `scripts/ci/run_repository_tests.py` auto-discovers both `scripts/tests/test_*.py` and `scripts/tests/test_*.rb`; existing PR CI runs Ruby packaging discovery and app-layer discovery without credentials.
- `.github/workflows/testflight.yml` is manual-only, checks out `main`, accepts only macOS, does not cancel active uploads, validates the existing secrets, unlocks the existing login keychain, runs packaging tests, calls `fastlane mac beta`, and moves the release tag only after success.
- VitalStride PR #441 / merge `9cfebd9e6ad5a3f3367753c9d0c09cad9e831e7e` is comparative evidence: it replaced fixed target profile names with canonical current-run values and added a credential-free freshness regression. VoxPocket differs by being a macOS `.pkg` path with one macOS app target and an installer certificate selector; no VitalStride path or decision is authoritative here.
- At baseline `ef1420234d2b56fddcf2a388eaabf97ec54126d4`, `project.yml` already declares recursive `VoxPocket` and `VoxPocketTests` source directories. `AppPersistenceStartup.swift`, `DefaultStageTextModelService.swift`, `MacOSAppScenes.swift`, `SettingsView.swift`, `StageModelRouting.swift`, `AppPersistenceStartupTests.swift`, and `RealtimeTranscriberConfigurationTests.swift` are tracked inside those directories but absent from the older committed generated project. CI and Fastlane regenerate from `project.yml` before app builds, so those seven files are already selected by the repository's runtime source of truth.
- Team Lead authorization comment `01a13bd0-6db3-72c8-8da5-b1bc102dcead` confirms that those seven memberships are current-version T002 source-of-truth synchronization in the already owned generated path, with no authorization to edit the files, dependencies, iOS behavior, or any other accepted boundary.
- Fastlane 2.241.0 defines `SharedValues::SIGH_NAME` in `fastlane/lib/fastlane/actions/get_provisioning_profile.rb`. `Sigh::Manager.install_profile` writes temporary `ENV["SIGH_NAME"]`; the real `GetProvisioningProfileAction.run` copies it into `Fastlane::Actions.lane_context[SharedValues::SIGH_NAME]` and returns the profile UUID. `fastlane/lib/fastlane/fast_file.rb` exposes `lane_context` and `SharedValues` to a Fastfile. The platform changes profile selection, not this shared-value key.

## Decision R-001: One macOS target-specific XcodeGen input

**Decision**: Define `VOXPOCKET_MAC_PROFILE_SPECIFIER` as the only runtime archive input for `PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]`. Keep the existing `iphoneos` profile setting unchanged.

**Rationale**: The shared app target needs one macOS-specific value without changing the paused iOS delivery contract. XcodeGen remains the truth source, and a target-specific build setting prevents a global profile override from affecting the wrong SDK.

**Alternatives considered**:

- Override global `PROVISIONING_PROFILE_SPECIFIER` in Fastlane. Rejected because it can affect both SDKs on the multiplatform target.
- Mutate the generated Xcode project during the lane. Rejected because it creates a second project-editing mechanism and violates the XcodeGen truth-source rule.
- Keep the fixed name and recreate a profile with that display name. Rejected because it preserves the machine/profile naming dependency that caused the incident.

## Decision R-002: Forced current-run acquisition and one canonical source

**Decision**: Fetch/create and install the macOS App Store profile with `force: true`, no `provisioning_name`, then read `lane_context[SharedValues::SIGH_NAME]`, require it to be non-empty before archive, shell-escape it for the custom XcodeGen setting, and reuse the same variable for export.

**Rationale**: A forced current-run profile reflects current capabilities and signing certificates. One canonical value makes archive and export agree and exposes a missing integration output before expensive build/upload work.

**Alternatives considered**:

- Retain the action-return fallback. Rejected because Fastlane 2.241.0 returns the profile UUID, not the installed display name.
- Read `ENV["sigh_#{APP_IDENTIFIER}_appstore_profile-name"]`. Rejected because Fastlane 2.241.0 does not publish that key; its temporary internal environment key is `SIGH_NAME`, and the supported Fastfile consumer boundary after the action is the shared-value lane context.
- Look up installed profiles independently after fetch. Rejected because it adds parsing and ambiguity after Fastlane has already published the target output.
- Log the resolved name for diagnosis. Rejected because failure can identify the missing contract without disclosing profile values.

## Decision R-003: Preserve the generic Mac Installer Distribution selector

**Decision**: Retain the already-landed `Mac Installer Distribution` export selector and personal-subject absence byte-for-byte. Neither the selector nor certificate/keychain behavior is an implementation path in this repair.

**Rationale**: The accepted selector already lets Xcode choose an existing valid installer identity for the export team while complying with the prohibition on committed personal account names. Rewriting it would widen the Fastfile repair beyond the failed profile-name consumer.

**Alternatives considered**:

- Keep the full subject. Rejected by repository protocol and portability requirements.
- Discover and inject a subject with `security` commands. Rejected because it expands workflow/keychain parsing, risks logging identity data, and is unnecessary when Xcode provides an automatic selector.
- Import or rotate an installer certificate. Rejected because host/keychain mutation is explicitly out of scope.

## Decision R-004: Static freshness plus behavior fixture

**Decision**: Use `scripts/tests/test_testflight_freshness.py` for cross-file static invariants and make `scripts/tests/test_testflight_packaging.rb` exercise the real `GetProvisioningProfileAction` class. The Ruby fixture stubs only `Sigh::Manager.start`, clears/restores actual lane context, publishes through `SharedValues::SIGH_NAME`, and returns a distinct UUID so a name/return-value mix-up fails.

**Rationale**: The Python file matches repository auto-discovery and the comparative incident guard; the Ruby fixture proves the pinned Fastlane producer/consumer boundary, fail-before-build behavior, and exact runtime option reuse without Apple access. Together they fail on both the historical fixed-name state and the post-merge fabricated-key regression without duplicating the release lane.

**Alternatives considered**:

- Use only static text assertions. Rejected because they cannot prove the lane fails before build or reuses the runtime value.
- Stub `GetProvisioningProfileAction` or make its return equal the display name. Rejected because either approach bypasses the class contract that regressed and can make a UUID/display-name mix-up pass.
- Use only Ruby fixtures. Rejected because the requested freshness guard spans project/workflow/Fastfile files and benefits from the repository's Python discovery.
- Run the real lane in CI. Rejected because it needs secrets, signs, mutates external state, uploads, and violates the Owner gate.

## Decision R-005: Preserve executable workflow behavior

**Decision**: Do not edit `.github/workflows/testflight.yml`; keep every executable line and comment unchanged.

**Rationale**: The workflow already passes the required secrets and calls the repaired lane. The defect is the project/Fastlane handoff, not trigger, runner, keychain, upload, or tag orchestration.

**Alternatives considered**:

- Export the profile name in GitHub Actions. Rejected because acquisition and consumption belong together inside the lane.
- Add new secrets or certificate inputs. Rejected by the issue acceptance and existing secret contract.

## Decision R-006: Separate implementation evidence from production proof

**Decision**: Complete content verification and reviewed PR delivery without credentials or external mutation. Keep the real release as a separately blocked task after merge and explicit Owner authorization.

**Rationale**: Static/fixture/unsigned evidence can prove implementation intent safely, while only the self-hosted runner and App Store Connect can prove final production success. The latter publishes a build and may refresh portal profile state.

## Decision R-007: No ADR, domain context, or dependency change

**Decision**: Do not edit domain context, architecture records, layer tech-context, dependency pins, or shared-ci.

**Rationale**: The repair uses existing VoxPocketApp/root-support ownership, XcodeGen truth, manual release policy, and review gates. It adds no product terminology, public API, package edge, or general repository rule.

## Decision R-008: Reconcile the stale generated source membership

**Decision**: The current baseline already contains the signing-setting substitution and exactly the seven reconciled memberships identified above. The repair performs read-only/idempotency verification and authorizes no XcodeGen source change, generated-project change, Swift edit, additional membership, or other semantic build-setting drift; any diff returns to Team Lead.

**Rationale**: The accepted implementation already reconciled the checked-in project with the repository's established XcodeGen source of truth. Reopening that owned surface is unnecessary for the Fastlane consumer repair and would violate the Team Lead's unrelated-path boundary.

## No Open Clarification

MY-1768, the Team Lead repair handoff, VoxPocket repository rules, current release code, run `38678678083`, pinned Fastlane 2.241.0 source, and comparative VitalStride evidence settle the current version's outcome, scope, compatibility, removed behavior, test shape, review path, and production authorization boundary. Runtime certificate/profile availability remains a post-merge operational fact, not a planning ambiguity.
