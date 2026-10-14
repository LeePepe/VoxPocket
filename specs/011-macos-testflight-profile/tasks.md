---

description: "Layer-scoped task graph for portable macOS TestFlight signing"

---

# Tasks: Portable macOS TestFlight signing

**Input**: Design documents from `specs/011-macos-testflight-profile/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/macos-signing-handoff.md`, `quickstart.md`, `checklists/requirements.md`

**Organization**: US1 establishes the current-run signing contract, US2 proves and publishes the unchanged reviewed candidate, and US3 records the separately Owner-authorized production result.

## Phase 1: User Story 1 - Release with the profile fetched in this run (Priority: P1)

**Goal**: One validated profile name fetched or created during the authorized macOS run drives both archive and export, while installer selection is portable and existing release behavior is preserved.

**Independent Test**: The historical fixed-name state fails the credential-free regression; the repaired state passes static and Ruby fixture coverage, XcodeGen regeneration, and unsigned verification without Apple access.

- [ ] T001 [US1] Add red-capable current-run signing regressions in `scripts/tests/test_testflight_freshness.py` and `scripts/tests/test_testflight_packaging.rb`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `_root support`; context `docs/architecture/tech-context.md` |
| Vertical slice | US1 |
| Files in scope | New `scripts/tests/test_testflight_freshness.py`; existing `scripts/tests/test_testflight_packaging.rb` |
| Files out of scope | Production Fastfile/project/workflow edits; other tests; policy/gate/discovery code; credentials; real profile/network/signing/upload operations |
| Interface impact | Test-only contract for `contracts/macos-signing-handoff.md`; no public product interface |
| Task-local acceptance | Tests are written before production edits and fail against the fixed-name/personal-subject baseline. They cover forced installed macOS profile acquisition without a requested display name, exact canonical output, nil/blank failure before build, shell-safe opaque transport, one archive/export value, macOS-only XcodeGen mapping, generic installer selector, and all preserved manual workflow/package/upload invariants. No existing assertion is removed or weakened. |
| Verification | `python3 -B scripts/tests/test_testflight_freshness.py` must demonstrate the red baseline; after T002/T003, run the focused Python file and the Fastlane-environment `packaging-ruby` command from `quickstart.md`. |
| Blocking edges | None. Defines the contract consumed by T002 and T003. |

- [ ] T002 [US1] Replace the fixed macOS Release profile setting with `VOXPOCKET_MAC_PROFILE_SPECIFIER` in `VoxPocket/project.yml` and regenerate `VoxPocket/VoxPocket.xcodeproj/project.pbxproj`

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `VoxPocketApp`; context `VoxPocket/tech-context.md` |
| Vertical slice | US1 |
| Files in scope | `VoxPocket/project.yml`; generated `VoxPocket/VoxPocket.xcodeproj/project.pbxproj` as required output only |
| Files out of scope | Direct generated-project edits; app/product source; packages; widget configuration; iOS profile migration; entitlements; bundle/team IDs; Fastlane/workflow/tests/docs |
| Interface impact | Internal archive boundary: `PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]` consumes `$(VOXPOCKET_MAC_PROFILE_SPECIFIER)`. Existing iPhoneOS Release setting remains unchanged. |
| Task-local acceptance | Base/Debug signing remains Automatic; app Release remains Manual + Apple Distribution; the only `project.yml` semantic change removes the macOS fixed display name. Generated output is produced by the recorded XcodeGen executable, is idempotent on a second run, and contains only the planned signing substitution plus membership for the seven baseline-tracked files named by R-008. No Swift source edit, additional membership, or other semantic build-setting drift is authorized; unsigned macOS/iOS build compatibility is preserved. |
| Verification | Run the XcodeGen/idempotency sequence in `quickstart.md`, `git diff --check`, and `scripts/verify --layer VoxPocketApp`. |
| Blocking edges | Depends on T001's red contract. Establishes the archive consumer required by T003. |

- [ ] T003 [US1] Make the mac lane validate and reuse its current-run profile in `fastlane/Fastfile`, preserve executable workflow behavior in `.github/workflows/testflight.yml`, and update `docs/testflight-release.md`

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | `_root support`; context `docs/architecture/tech-context.md` |
| Vertical slice | US1 |
| Files in scope | `fastlane/Fastfile`; comment-only signing-description correction in `.github/workflows/testflight.yml`; `docs/testflight-release.md` |
| Files out of scope | Workflow executable lines; keychain commands; secrets; iOS lane behavior; project/product/package paths; dependency pins; release tag/build-number/upload/distribution behavior; Developer Portal cleanup |
| Interface impact | Produces the T002 archive key from the canonical current-run profile name and reuses that name for export; replaces the personal installer subject with `Mac Installer Distribution`. No public product interface. |
| Task-local acceptance | The mac profile request is `platform: "macos"`, forced, installed, and contains no fixed requested name; the canonical profile-name output is non-empty or fails before `build_app` without disclosure; archive uses a shell-escaped `VOXPOCKET_MAC_PROFILE_SPECIFIER`; export reuses the exact variable; no action-return fallback/global profile override/personal subject remains; workflow behavior is unchanged; existing secret/keychain/package/upload/tag behavior is preserved; T001 is green. |
| Verification | Focused Python/Ruby commands and `ruby -c fastlane/Fastfile`; inspect the workflow diff as comment-only; `scripts/verify --policy`; `git diff --check`. |
| Blocking edges | Depends on T001 and T002. Blocks assembled verification T004. |

**Checkpoint**: US1 is independently demonstrable without Apple credentials: the fixed-name baseline fails, repaired tests pass, the project is regenerated, and no release is dispatched.

## Phase 2: User Story 2 - Detect signing drift before a release (Priority: P1)

**Goal**: The complete credential-free candidate is verified, frozen, independently reviewed before publication, and delivered as an unchanged important PR with exact-head evidence.

**Independent Test**: All focused/repository gates pass on one frozen tree, AI Reviewer grants exact content `PASS` plus publication permission, and the published tree/SHA/PR head are identical with Owner review required.

- [ ] T004 [US2] Freeze, verify, review, and publish the assembled candidate for `VoxPocket/project.yml`, `VoxPocket/VoxPocket.xcodeproj/project.pbxproj`, `fastlane/Fastfile`, `.github/workflows/testflight.yml`, `scripts/tests/test_testflight_freshness.py`, `scripts/tests/test_testflight_packaging.rb`, and `docs/testflight-release.md`

### T004 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | Cross-layer integration/delivery verification; no new change-owner path |
| Vertical slice | US2 |
| Files in scope | Verification-only access to every T001–T003 path; frozen-tree manifest; after publication permission only, task branch/commit and PR metadata |
| Files out of scope | New source repair inside T004; commit/push/PR mutation before permission; secrets; keychain/certificate/profile state; real TestFlight dispatch; unrelated cleanup |
| Interface impact | None; verifies the assembled internal contract and repository delivery rules. |
| Task-local acceptance | **Stage A:** run the entire `quickstart.md` credential-free sequence; confirm no test removal/weakening, no new secret/host step, no personal subject, XcodeGen idempotency, and exact changed-path scope; freeze the uncommitted tree/manifest and obtain AI Reviewer exact content `PASS` plus explicit publication permission. Any content change returns to Stage A. **Stage B:** commit/push only the unchanged reviewed tree, create/update a non-Draft important PR with complete template and Owner review, prove reviewed tree = commit tree and local SHA = remote branch OID = PR `headRefOid`, then hand to PR Manager. Do not dispatch or claim TestFlight success. |
| Verification | `python3 scripts/ci/run_repository_tests.py app-python`; focused Ruby discovery; `scripts/verify --policy`; `scripts/verify --layer VoxPocketApp`; `scripts/verify`; `scripts/verify --all`; exact content verdict/permission; PR identity and required-check evidence. |
| Blocking edges | Depends on T001–T003. Stage A blocks publication; Owner approval and required checks block merge; T005 remains separately blocked. |

**Checkpoint**: US2 completes when the exact reviewed candidate is published unchanged and accepted through the repository's important-PR gates. Production release evidence is not yet claimed.

## Phase 3: User Story 3 - Record the production proof under Owner control (Priority: P1)

**Goal**: Prove the merged repair on the real macOS runner/App Store Connect path without broadening implementation authority.

**Independent Test**: After merge and explicit Owner authorization, one manual run on `main` records successful upload/processing, run URL, exact head SHA, and build number.

- [ ] T005 [US3] After reviewed merge and explicit Owner authorization, execute and record the production result for `.github/workflows/testflight.yml`

### T005 metadata

| Field | Contract |
|---|---|
| Owning layer/scope | Owner-controlled root-support production validation; no repository writer |
| Vertical slice | US3 |
| Files in scope | Execution-only use of `.github/workflows/testflight.yml`; issue evidence record |
| Files out of scope | Any dispatch before consent; repository edits; runner/keychain/certificate/profile cleanup or mutation beyond lane behavior; secret/profile/certificate/keychain disclosure |
| Interface impact | None; exercises the reviewed release path on merged `main`. |
| Task-local acceptance | Evidence proves reviewed implementation merged to `main`, explicit current Owner authorization, one manual macOS run, exact run head, `.pkg` archive/export, terminal TestFlight upload/processing success, and build number. Only non-sensitive warnings are recorded. A failure is returned through Team Lead to the original FS; it is not repaired in this task. |
| Verification | Consent reference, GitHub Actions run URL, exact `main` SHA, terminal conclusion, and processed build number. Never attach raw secrets, profile values/contents, certificate identifiers, keychain output, or credential paths. |
| Blocking edges | Depends on T004, PR Manager merge, and explicit Owner authorization. It remains blocked and undispatched until all three hold. |

## Dependencies & Execution Order

```text
T001 root-support red regression
  -> T002 VoxPocketApp XcodeGen handoff
       -> T003 root-support Fastlane/workflow prose/docs repair
            -> T004-A full credential-free verification + frozen content review
                 -> AI Reviewer PASS + publication permission
                      -> T004-B unchanged commit/push/non-Draft important PR
                           -> Owner approval + PR Manager required checks/merge
                                -> explicit Owner release authorization
                                     -> T005 production run evidence
```

- T001 precedes production edits so the historical state is evidenced red.
- T002 owns only the VoxPocketApp truth source and generated output.
- T003 owns only root-support release surfaces and consumes T002's exact key.
- T004 may not repair either scope; failures route back to T002 or T003.
- T005 is not a Fullstack implementation task and is never implicitly authorized by merge.
- No task is marked `[P]` because each consumes the preceding signing contract or external gate.

## Acceptance Traceability

| Spec acceptance | Slice | Tasks | Verification surface |
|---|---|---|---|
| US1/AC1, US1/AC2, US1/AC3; FR-001, FR-002, FR-003, FR-004; RB-001, RB-002 | US1 | T001, T002, T003 | red/green profile acquisition, canonical-name fail-closed contract, archive/export reuse |
| US1/AC4, US1/AC5; FR-005, FR-006, FR-007; RB-003 | US1 | T001, T002, T003 | shell-safe value, existing-key contract, generic installer selector, no personal subject |
| US2/AC1, US2/AC2; FR-010, FR-011, FR-012 | US2 | T001, T002, T003, T004 | discovered Python/Ruby regressions, regenerated project, policy/app/full gates |
| US2/AC3, US2/AC4; FR-008, FR-009; RB-004 | US2 | T001, T003, T004 | preserved workflow/package/build/upload/tag assertions and credential-free verification |
| US3/AC1, US3/AC2, US3/AC3; FR-013 | US3 | T005 | consent, merged head, run URL, terminal result, build number, no early dispatch |
| SC-001, SC-002, SC-003 | US1/US2 | T001, T002, T003, T004 | exact candidate local evidence and absence checks |
| SC-004 | US2 | T004 | non-Draft important PR, Owner approval, required checks on exact head |
| SC-005 | US3 | T005 | Owner-authorized production evidence |

## Implementation Strategy

1. T001 locks the failure contract before production changes.
2. T002 establishes the macOS-only XcodeGen consumer and deterministic generated output.
3. T003 supplies the current-run value and completes credential-free regression coverage without changing release orchestration.
4. T004 freezes and reviews the candidate before publication, then publishes only the unchanged tree for Owner/PR Manager gates.
5. T005 stays externally blocked until merge and explicit Owner authorization, then records the issue's final production proof.

## Format Validation

- Total tasks: 5 (US1: 3, US2: 1, US3: 1).
- Every executable row uses `- [ ] Txxx [US#]` with exact paths.
- Every task has one owning layer/scope, exclusions, interface impact, task-local acceptance, verification, and blocking edges.
- The dependency graph is acyclic; there are no valid parallel opportunities.
