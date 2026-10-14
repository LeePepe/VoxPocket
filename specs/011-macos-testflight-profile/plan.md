# Implementation Plan: Portable macOS TestFlight signing

**Feature**: `011-macos-testflight-profile` | **Date**: 2026-10-15 | **Spec**: [`spec.md`](./spec.md)

**Baseline**: VoxPocket `main` `ef1420234d2b56fddcf2a388eaabf97ec54126d4`

**Input**: MY-1768 revision 3, failed TestFlight run `38598643529`, Team Lead handoff, and repository evidence in [`research.md`](./research.md)

## Summary

Replace VoxPocket's macOS archive/export dependence on the fixed profile display name with one target-specific value sourced from the profile fetched or created during the current authorized release run. XcodeGen's app Release configuration consumes that value, Fastlane validates and shell-safely injects it into archive and reuses it for export, and the installer export uses a team-agnostic automatic selector instead of a personal certificate subject. Credential-free Python and Ruby regressions guard the handoff and preserve the manual macOS-only workflow. Production proof remains a separate post-merge, Owner-authorized manual TestFlight run.

## Technical Context

**Languages/tooling**: Ruby/Fastlane, Python 3.11+ `unittest`, YAML/XcodeGen, GitHub Actions, Swift 6.2 app project

**Primary dependencies**: Fastlane `get_provisioning_profile`/gym/pilot, Ruby `Shellwords`, XcodeGen, existing App Store Connect API-key secrets, shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`

**Storage/data**: No repository data model or migration; installed provisioning profiles and build artifacts are ephemeral release-run state

**Testing**: New static Python signing-freshness contract, extended Fastlane Ruby fixtures, repository app-test discovery, policy gate, XcodeGen idempotency, unsigned app build in CI, exact-head required checks

**Target platform**: macOS 26 TestFlight on the existing self-hosted Apple Silicon runner; iOS delivery remains disabled

**Project type**: macOS/iOS app repository with root release support and a VoxPocketApp XcodeGen shell

**Performance goals**: No runtime performance change; fail before archive if the canonical profile name is unavailable

**Constraints**: TestFlight-only delivery; no local archive/upload; no new secrets; no certificate or keychain mutation; no personal account names; manual `main` dispatch only; Owner approval for CODEOWNERS paths; heavy signed validation only after merge and explicit Owner authorization

**Scope**: one macOS profile handoff, one installer selector correction, credential-free regressions, generated-project synchronization, accurate release prose, and post-merge evidence

## Constitution Check — Before Research

| Principle / repository rule | Result | Plan response |
|---|---|---|
| I Immutability | PASS | No runtime object or persisted user data is changed. |
| II Layer direction | PASS | `VoxPocketApp` owns `VoxPocket/project.yml`; root support owns Fastlane, workflow, scripts, and release docs. No package dependency changes. |
| III Concurrency safety | PASS | No app runtime or concurrency code changes. |
| IV Privacy of voice/text | PASS | Release tests and evidence never access or log user audio, transcripts, or refined text. |
| V Secrets/vendor hygiene | PASS | Existing secret names are reused in memory; no key, profile contents, certificate contents, or personal account name is committed or printed. |
| VI Boundary validation | PASS | The canonical external profile-name output is validated as non-empty before archive. |
| XcodeGen source of truth | PASS | `VoxPocket/project.yml` changes first and the generated project is regenerated, never hand-edited. |
| TestFlight-only delivery | PASS | Local verification is credential-free and unsigned; the real release remains post-merge and Owner-authorized. |
| Existing behavior preserved | PASS | Manual/macOS-only gating, build numbering, packaging, upload, and tag movement remain unchanged. |
| Important paths need Owner | PASS | The non-Draft PR carries Owner review for `fastlane/**`, `.github/**`, and `VoxPocket/project.yml`. |

No constitutional exception is requested.

## Research Decisions

The evidence and alternatives are recorded in [`research.md`](./research.md). Binding choices:

1. **R-001 — One macOS target-specific interface**: `VOXPOCKET_MAC_PROFILE_SPECIFIER` is the sole archive input for the macOS Release provisioning-profile setting. The existing iOS setting is unchanged.
2. **R-002 — Current-run canonical source**: the mac lane force-refreshes and installs the App Store profile without requesting a fixed display name, resolves the canonical Fastlane profile-name output, validates it as non-empty before `build_app`, shell-escapes it for archive, and reuses the same variable for export. No action-return fallback remains.
3. **R-003 — Portable installer selector**: export uses the automatic selector `Mac Installer Distribution`, preserving installer signing while removing the prohibited personal subject string. It does not import or modify an identity.
4. **R-004 — Two complementary regressions**: a new auto-discovered Python freshness contract guards static cross-file wiring and workflow invariants; the existing Ruby fixture guards lane behavior and exact options without signing or network access.
5. **R-005 — Workflow behavior unchanged**: `.github/workflows/testflight.yml` receives at most comment-only signing-description correction; executable trigger, gate, secrets, keychain preparation, lane invocation, and tag movement stay byte-for-byte behaviorally unchanged.
6. **R-006 — Production proof is external**: content delivery completes through credential-free review and PR gates; only the Owner may authorize the post-merge manual run required for final issue acceptance.
7. **R-007 — No ADR/domain-context change**: this is a release-contract repair inside existing VoxPocketApp/root-support ownership and introduces no durable product term, public interface, or dependency edge.
8. **R-008 — Exact generated-project reconciliation**: regeneration may add only the seven baseline-tracked source memberships named in `research.md` alongside the planned macOS signing-setting substitution. It authorizes no Swift edit, additional membership, or other semantic build-setting drift.

## Design and Interfaces

The exact cross-file handoff is [`contracts/macos-signing-handoff.md`](./contracts/macos-signing-handoff.md). Conceptual state is in [`data-model.md`](./data-model.md).

### VoxPocketApp project seam

- `VoxPocket/project.yml` keeps base/Debug Automatic signing and Release Manual + Apple Distribution.
- Only the `macosx` Release profile specifier consumes `$(VOXPOCKET_MAC_PROFILE_SPECIFIER)`; the `iphoneos` profile setting remains unchanged.
- `VoxPocket/VoxPocket.xcodeproj/project.pbxproj` is regenerated from XcodeGen and committed only as generated synchronization evidence: the signing substitution plus membership for `AppPersistenceStartup.swift`, `DefaultStageTextModelService.swift`, `MacOSAppScenes.swift`, `SettingsView.swift`, `StageModelRouting.swift`, `AppPersistenceStartupTests.swift`, and `RealtimeTranscriberConfigurationTests.swift`, all already tracked and selected by the baseline directory-source declarations.

### Root-support release seam

- The mac lane fetches/creates the App Store profile with the existing API key, team, app identifier, `platform: "macos"`, `force: true`, and installation enabled, without `provisioning_name`.
- It reads `sigh_#{APP_IDENTIFIER}_appstore_profile-name`, rejects nil/blank before archive without logging the value, and carries the opaque value through `Shellwords.escape` as `VOXPOCKET_MAC_PROFILE_SPECIFIER`.
- `export_options.provisioningProfiles[APP_IDENTIFIER]` reuses the same validated variable.
- `installerSigningCertificate` becomes the automatic selector `Mac Installer Distribution`; no personal subject or keychain discovery output is stored.

### Regression and policy seam

- `scripts/tests/test_testflight_freshness.py` is auto-discovered by `python3 scripts/ci/run_repository_tests.py app-python` and guards the workflow/project/Fastfile contract.
- `scripts/tests/test_testflight_packaging.rb` captures profile requests, canonical-name failure, archive/export options, and installer selector behavior through fixtures.
- No test invokes App Store Connect, signs an archive, unlocks a keychain, uploads a build, or moves a tag.

## Implementation Slices

### Slice US1 — Current-run profile drives signed package creation

Establish the red regression contract, update the XcodeGen macOS Release seam, regenerate the project, and repair the Fastlane mac lane so current-run acquisition, archive, export, and installer selection share one fail-closed signing contract. Preserve the iOS lane and every manual release invariant.

### Slice US2 — Deterministic pre-release protection and reviewed delivery

Run focused regressions, policy, app-layer and full repository verification; prove generated-project idempotency; update release prose; freeze one local candidate for independent prepublication content review; after exact `PASS` and publication permission, publish the unchanged important PR with Owner review and exact local/remote/PR SHA identity.

### Slice US3 — Owner-controlled production validation

After reviewed merge and explicit current Owner authorization, run the existing manual macOS workflow once on `main` and record only the run URL, exact head SHA, build number, terminal conclusion, and distribution warnings. This slice has no repository edit and is not schedulable before its external gates.

## Acceptance Traceability

| Acceptance IDs | Slice | Tasks | Evidence |
|---|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC5; FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007; RB-001, RB-002, RB-003 | US1 | T001, T002, T003 | red/green static contract, Ruby fixture, project regeneration, shell-safe current-run reuse |
| US2/AC1, US2/AC2, US2/AC3, US2/AC4; FR-008, FR-009, FR-010, FR-011, FR-012; RB-004 | US2 | T001, T003, T004 | discovered regressions, workflow guards, policy/app/full verification, frozen-tree review, important PR exact-head proof |
| US3/AC1, US3/AC2, US3/AC3; FR-013 | US3 | T005 | Owner consent record, merged `main` SHA, Actions run URL, terminal result, build number |
| SC-001, SC-002, SC-003 | US1/US2 | T001, T002, T003, T004 | credential-free candidate evidence and absence checks |
| SC-004 | US2 | T004 | non-Draft important PR, Owner approval, required checks on head SHA |
| SC-005 | US3 | T005 | explicitly authorized production evidence |

Every acceptance criterion maps to at least one task and one evidence surface.

## Verification Strategy

The runnable sequence and expected outcomes are in [`quickstart.md`](./quickstart.md). Required implementation evidence:

1. historical fixed-name state fails the new freshness contract before implementation;
2. focused Python and Ruby signing regressions pass without credentials;
3. Fastfile syntax passes;
4. XcodeGen regeneration is clean and idempotent with the recorded executable;
5. `scripts/verify --policy`, `scripts/verify --layer VoxPocketApp`, `scripts/verify`, and `scripts/verify --all` exit 0 without local signed archive/upload;
6. the frozen local candidate receives exact content `PASS` and publication permission before commit/push/PR;
7. reviewed tree equals published commit tree, and local SHA equals remote branch OID equals PR `headRefOid`;
8. required checks and Owner approval are green on the exact PR head;
9. after merge and explicit Owner authorization, one manual workflow run supplies the production evidence required by US3.

## Project Structure

```text
specs/011-macos-testflight-profile/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── macos-signing-handoff.md
├── checklists/
│   └── requirements.md
└── tasks.md

VoxPocket/project.yml                            # VoxPocketApp truth source
VoxPocket/VoxPocket.xcodeproj/project.pbxproj    # regenerated output only
fastlane/Fastfile                                # root-support lane contract
.github/workflows/testflight.yml                 # comment-only signing description; executable behavior preserved
scripts/tests/test_testflight_freshness.py        # new static credential-free regression
scripts/tests/test_testflight_packaging.rb        # existing behavior fixture extended
docs/testflight-release.md                        # operator contract update
```

**Structure Decision**: one VoxPocketApp task owns the XcodeGen truth source and generated output; root-support tasks own Fastlane/workflow/tests/docs. No product package or new dependency is introduced.

## Constitution Check — After Design

PASS with no exception. The design keeps dependencies unchanged, validates the external profile-name boundary, preserves privacy and secret handling, removes a personal account subject, uses XcodeGen as truth, confines real signing/upload to an Owner-authorized post-merge run, and routes all important paths through Owner review.

## Dependencies and External Gates

- Repository base: VoxPocket `main` `ef1420234d2b56fddcf2a388eaabf97ec54126d4`.
- Repo contract: shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`.
- External Swift test dependency: AppleUITesting `e6be2fcdf83341a9f3000a4cc489237655461a07`; its existing release-workflow checkout omission is a pre-existing risk and not repaired here.
- Runtime secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `KEYCHAIN_PASSWORD`; no additions.
- Runner state: valid existing Apple Distribution and Mac Installer Distribution private keys for team `4Z8GG667QD`.
- Review: AI Reviewer exact-revision spec gate before Team Lead/FS; exact candidate content review before publication; Owner approval for the important PR.
- Production: merge plus explicit Owner authorization before the manual TestFlight run.

## Risks and Escalation Conditions

| Risk | Mitigation / escalation |
|---|---|
| Canonical Fastlane profile-name output changes or is empty | Fail before archive; fixture and static contract catch missing/fallback behavior. If the installed Fastlane does not publish it, return to Team Lead rather than add another source silently. |
| Generic installer selector finds no valid identity | The authorized run fails without keychain mutation; return runner/certificate evidence to Team Lead/Owner. Do not import or select a personal subject in code. |
| XcodeGen regeneration produces drift beyond the planned signing substitution and seven allowlisted baseline memberships | Stop and report the generator version and diff; do not hand-edit or absorb any additional output. |
| Important-path approval absent | Keep the PR in `owner-review`; never bypass CODEOWNERS/ruleset protection. |
| Manual run fails after merge | Record the exact run/head/error class without sensitive values and route current-version repair to the original FS through Team Lead. |
| AppleUITesting workflow checkout remains unpinned | Keep it unchanged in this version; report only if it blocks required verification. |

## Complexity Tracking

No constitutional violation or new architecture complexity requires an exception.
