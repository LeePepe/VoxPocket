# Implementation Plan: Portable macOS TestFlight signing

**Feature**: `011-macos-testflight-profile` | **Date**: 2026-10-15 | **Spec**: [`spec.md`](./spec.md)

**Baseline**: VoxPocket `main` `20f9c36e9c60e2c2dcee2514d83138826caa91f6`

**Input**: MY-1768 revision 4, post-merge TestFlight run `38678678083`, Team Lead repair handoff, and repository evidence in [`research.md`](./research.md)

## Summary

VoxPocket `main` already carries the accepted target-specific XcodeGen handoff and portable installer selector, but its Fastlane consumer assumes an environment key that Fastlane 2.241.0 does not publish. Repair only that current-run seam: read the installed profile display name from `lane_context[SharedValues::SIGH_NAME]`, validate it before archive, shell-safely inject it into the existing archive key, and reuse it for export. Credential-free Python and Ruby regressions assert the real Fastlane action contract by class while preserving the manual macOS-only workflow. Production proof remains a separate post-merge, Owner-authorized manual TestFlight run.

## Technical Context

**Languages/tooling**: Ruby/Fastlane, Python 3.11+ `unittest`, YAML/XcodeGen, GitHub Actions, Swift 6.2 app project

**Primary dependencies**: Fastlane `get_provisioning_profile`/gym/pilot, Ruby `Shellwords`, XcodeGen, existing App Store Connect API-key secrets, shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`

**Storage/data**: No repository data model or migration; installed provisioning profiles and build artifacts are ephemeral release-run state

**Testing**: Static Python signing-freshness contract, Fastlane Ruby fixtures that exercise the real `GetProvisioningProfileAction` class while stubbing only `Sigh::Manager.start`, repository app-test discovery, policy gate, XcodeGen idempotency, unsigned app build in CI, exact-head required checks

**Target platform**: macOS 26 TestFlight on the existing self-hosted Apple Silicon runner; iOS delivery remains disabled

**Project type**: macOS/iOS app repository with root release support and a VoxPocketApp XcodeGen shell

**Performance goals**: No runtime performance change; fail before archive if the canonical profile name is unavailable

**Constraints**: TestFlight-only delivery; no local archive/upload; no new secrets; no certificate or keychain mutation; no personal account names; manual `main` dispatch only; Owner approval for CODEOWNERS paths; heavy signed validation only after merge and explicit Owner authorization

**Scope**: the Fastlane macOS profile-name consumer, its Python/Ruby credential-free regressions, read-only preservation checks for every already-landed adjacent surface, reviewed delivery, and post-merge evidence

## Constitution Check — Before Research

| Principle / repository rule | Result | Plan response |
|---|---|---|
| I Immutability | PASS | No runtime object or persisted user data is changed. |
| II Layer direction | PASS | Root support owns the Fastlane and test repair. The existing `VoxPocketApp` consumer is verified read-only; no package dependency changes. |
| III Concurrency safety | PASS | No app runtime or concurrency code changes. |
| IV Privacy of voice/text | PASS | Release tests and evidence never access or log user audio, transcripts, or refined text. |
| V Secrets/vendor hygiene | PASS | Existing secret names are reused in memory; no key, profile contents, certificate contents, or personal account name is committed or printed. |
| VI Boundary validation | PASS | The canonical external profile-name output is validated as non-empty before archive. |
| XcodeGen source of truth | PASS | The current baseline's synchronized `VoxPocket/project.yml` and generated project are verified unchanged; neither is edited. |
| TestFlight-only delivery | PASS | Local verification is credential-free and unsigned; the real release remains post-merge and Owner-authorized. |
| Existing behavior preserved | PASS | Manual/macOS-only gating, build numbering, packaging, upload, and tag movement remain unchanged. |
| Important paths need Owner | PASS | The non-Draft PR carries Owner review for `fastlane/**`; no other important path is changed. |

No constitutional exception is requested.

## Research Decisions

The evidence and alternatives are recorded in [`research.md`](./research.md). Binding choices:

1. **R-001 — One macOS target-specific interface**: `VOXPOCKET_MAC_PROFILE_SPECIFIER` is the sole archive input for the macOS Release provisioning-profile setting. The existing iOS setting is unchanged.
2. **R-002 — Current-run canonical source**: the mac lane force-refreshes and installs the App Store profile without requesting a fixed display name, then reads `lane_context[SharedValues::SIGH_NAME]`, the display-name output published by Fastlane 2.241.0's real `GetProvisioningProfileAction`. It validates the value as non-empty before `build_app`, shell-escapes it for archive, and reuses the same variable for export. The action return is a UUID, so no action-return or fabricated environment-key fallback is allowed.
3. **R-003 — Preserve portable installer selector**: export already uses the automatic selector `Mac Installer Distribution`; the repair keeps it byte-identical and does not import, select, or modify an identity.
4. **R-004 — Two complementary regressions**: the auto-discovered Python freshness contract guards static cross-file wiring and workflow invariants; the Ruby fixture invokes the real `GetProvisioningProfileAction`, stubs only `Sigh::Manager.start` at the external acquisition boundary, and proves the shared-value lane-context contract and exact lane options without signing or network access.
5. **R-005 — Workflow behavior unchanged**: `.github/workflows/testflight.yml` is read-only in this repair; executable trigger, gate, secrets, keychain preparation, lane invocation, comments, and tag movement stay byte-for-byte unchanged.
6. **R-006 — Production proof is external**: content delivery completes through credential-free review and PR gates; only the Owner may authorize the post-merge manual run required for final issue acceptance.
7. **R-007 — No ADR/domain-context change**: this is a release-contract repair inside existing VoxPocketApp/root-support ownership and introduces no durable product term, public interface, or dependency edge.
8. **R-008 — Preserve exact generated-project reconciliation**: the current baseline already contains the signing substitution and seven baseline-tracked memberships named in `research.md`. This repair verifies them read-only and authorizes no XcodeGen/project/Swift mutation or generated drift.

## Design and Interfaces

The exact cross-file handoff is [`contracts/macos-signing-handoff.md`](./contracts/macos-signing-handoff.md). Conceptual state is in [`data-model.md`](./data-model.md).

### VoxPocketApp project seam

- `VoxPocket/project.yml` already keeps base/Debug Automatic signing and Release Manual + Apple Distribution.
- Only the `macosx` Release profile specifier already consumes `$(VOXPOCKET_MAC_PROFILE_SPECIFIER)`; the `iphoneos` profile setting remains unchanged.
- `VoxPocket/VoxPocket.xcodeproj/project.pbxproj` already contains the XcodeGen signing synchronization and seven baseline-tracked memberships. Both project files are read-only preservation surfaces for this repair.

### Root-support release seam

- The mac lane fetches/creates the App Store profile with the existing API key, team, app identifier, `platform: "macos"`, `force: true`, and installation enabled, without `provisioning_name`.
- It reads `lane_context[SharedValues::SIGH_NAME]`, rejects nil/blank before archive without logging the value, and carries the opaque value through `Shellwords.escape` as `VOXPOCKET_MAC_PROFILE_SPECIFIER`.
- It does not read a fabricated `sigh_<app-id>_appstore_profile-name` environment key or use the action return, which is the profile UUID, as the display name.
- `export_options.provisioningProfiles[APP_IDENTIFIER]` reuses the same validated variable.
- The already-landed `installerSigningCertificate: "Mac Installer Distribution"` selector and personal-subject absence remain byte-identical; this repair does not select, discover, or modify an installer identity.

### Regression and policy seam

- `scripts/tests/test_testflight_freshness.py` is auto-discovered by `python3 scripts/ci/run_repository_tests.py app-python` and guards the workflow/project/Fastfile contract.
- `scripts/tests/test_testflight_packaging.rb` invokes the real Fastlane profile action while stubbing only `Sigh::Manager.start`, clears/restores actual lane context, publishes the display name through `SharedValues::SIGH_NAME`, returns a distinct fixture UUID, and captures canonical-name failure, archive/export options, and installer selector behavior.
- No test invokes App Store Connect, signs an archive, unlocks a keychain, uploads a build, or moves a tag.

## Implementation Slices

### Slice US1 — Current-run profile drives signed package creation

Establish the red current-main regression contract, verify the existing XcodeGen macOS Release seam without changing it, and repair the Fastlane mac lane so the real action's current-run display name drives archive and export through the existing fail-closed signing contract. Preserve the installer selector, iOS lane, and every manual release invariant.

### Slice US2 — Deterministic pre-release protection and reviewed delivery

Run focused regressions, policy, app-layer and full repository verification; prove the generated project remains unchanged and idempotent; freeze one local candidate for independent prepublication content review; after exact `PASS` and publication permission, publish the unchanged important PR with Owner review and exact local/remote/PR SHA identity.

### Slice US3 — Owner-controlled production validation

After reviewed merge and explicit current Owner authorization, run the existing manual macOS workflow once on `main` and record only the run URL, exact head SHA, build number, terminal conclusion, and distribution warnings. This slice has no repository edit and is not schedulable before its external gates.

## Acceptance Traceability

| Acceptance IDs | Slice | Tasks | Evidence |
|---|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC5; FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007; RB-001, RB-002, RB-003 | US1 | T001, T002, T003 | red/green static contract, real-action Ruby fixture, project no-diff verification, shell-safe current-run reuse |
| US2/AC1, US2/AC2, US2/AC3, US2/AC4; FR-008, FR-009, FR-010, FR-011, FR-012; RB-004 | US2 | T001, T003, T004 | discovered regressions, workflow guards, policy/app/full verification, frozen-tree review, important PR exact-head proof |
| US3/AC1, US3/AC2, US3/AC3; FR-013 | US3 | T005 | Owner consent record, merged `main` SHA, Actions run URL, terminal result, build number |
| SC-001, SC-002, SC-003 | US1/US2 | T001, T002, T003, T004 | credential-free candidate evidence and absence checks |
| SC-004 | US2 | T004 | non-Draft important PR, Owner approval, required checks on head SHA |
| SC-005 | US3 | T005 | explicitly authorized production evidence |

Every acceptance criterion maps to at least one task and one evidence surface.

## Verification Strategy

The runnable sequence and expected outcomes are in [`quickstart.md`](./quickstart.md). Required implementation evidence:

1. current `main`'s fabricated environment-key consumer fails the repaired freshness contract before implementation, while the historical fixed-name guard remains intact;
2. focused Python and real-action Ruby signing regressions pass without credentials;
3. Fastfile syntax passes;
4. XcodeGen idempotency verification with the recorded executable produces zero diff from the current project bytes;
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

VoxPocket/project.yml                            # read-only VoxPocketApp truth source
VoxPocket/VoxPocket.xcodeproj/project.pbxproj    # read-only generated output
fastlane/Fastfile                                # root-support lane contract
.github/workflows/testflight.yml                 # read-only executable behavior
scripts/tests/test_testflight_freshness.py        # static credential-free regression repair
scripts/tests/test_testflight_packaging.rb        # real-action behavior fixture repair
docs/testflight-release.md                        # read-only operator contract
```

**Structure Decision**: root-support tasks own the Fastlane/test repair; the VoxPocketApp project, workflow, and docs are preservation surfaces only. No product package, new dependency, or additional implementation writer is introduced.

## Constitution Check — After Design

PASS with no exception. The design keeps dependencies unchanged, validates the external profile-name boundary, preserves privacy and secret handling, retains the already-landed personal-subject absence and generic installer selector unchanged, keeps XcodeGen as the read-only truth source, confines real signing/upload to an Owner-authorized post-merge run, and routes the Fastlane important path through Owner review.

## Dependencies and External Gates

- Repository base: VoxPocket `main` `20f9c36e9c60e2c2dcee2514d83138826caa91f6`.
- Repo contract: shared-ci `6e354f476bc53d68f0f09fc231d5cd938466af9c`.
- External Swift test dependency: AppleUITesting `e6be2fcdf83341a9f3000a4cc489237655461a07`; its existing release-workflow checkout omission is a pre-existing risk and not repaired here.
- Runtime secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `KEYCHAIN_PASSWORD`; no additions.
- Runner state: valid existing Apple Distribution and Mac Installer Distribution private keys for team `4Z8GG667QD`.
- Review: AI Reviewer exact-revision spec gate before Team Lead/FS; exact candidate content review before publication; Owner approval for the important PR.
- Production: merge plus explicit Owner authorization before the manual TestFlight run.

## Risks and Escalation Conditions

| Risk | Mitigation / escalation |
|---|---|
| Fastlane's `SharedValues::SIGH_NAME` lane-context contract changes or is empty | Fail before archive; the real-action fixture and static contract catch missing/fallback behavior. If the pinned Fastlane does not publish it, return to Team Lead rather than add another source silently. |
| Generic installer selector finds no valid identity | The authorized run fails without keychain mutation; return runner/certificate evidence to Team Lead/Owner. Do not import or select a personal subject in code. |
| XcodeGen verification produces any diff from the current synchronized baseline | Stop and report the generator version and diff; do not hand-edit, absorb output, or widen the repair. |
| Important-path approval absent | Keep the PR in `owner-review`; never bypass CODEOWNERS/ruleset protection. |
| Manual run fails after merge | Record the exact run/head/error class without sensitive values and route current-version repair to the original FS through Team Lead. |
| AppleUITesting workflow checkout remains unpinned | Keep it unchanged in this version; report only if it blocks required verification. |

## Complexity Tracking

No constitutional violation or new architecture complexity requires an exception.
