# Feature Specification: Required PR coverage for every VoxPocket test file

**Feature**: `010-ci-test-coverage`  
**Created**: 2026-10-13  
**Status**: Draft for independent spec/plan review  
**Input**: MY-1607 revision 10. Revision 9 supplied the product intent; revision 10 adds the Team Lead planning handoff without changing that intent.  
**Baseline**: `LeePepe/VoxPocket` at `ea88c649ca4faca45d2265b667cc83712dbe5a68`

Stable IDs in this document are append-only. Plan, tasks, verification, and review findings MUST cite them exactly.

## Decisions and authority

- **D-001 — Owner rule (MY-1607, 2026-10-13)**: every test file in the repository MUST execute in a required PR-time CI gate. A test file reached only by a manual or non-required workflow is a defect.
- **D-002 — Dispatcher retirement (`.specify/memory/constitution.md`, Amendment 2026-09-20; Owner commit `d8a12fbba05b2a1972ff5ec159f1239d74b54551`)**: the duplicate PR-comment dispatcher workflow and its auto-fix configuration are retired; deterministic hook checks remain direct.
- **D-003 — Release authority (MY-1607 and repository red lines)**: the TestFlight gate message and behavior are correct. This work MUST NOT authorize iOS TestFlight, change delivery behavior, archive/install a delivery build locally, or expose credentials, screenshots, audio, transcripts, or refined text.

## Actors and outcome

- **Maintainer / PR author**: receives required-check failures whenever any repository test regresses or a newly added test under an auto-discovered test directory is not runnable.
- **Owner / release operator**: can rerun the manual TestFlight workflow after merge knowing that the packaging contract already passed on the PR head.
- **Product user**: experiences no runtime, data, configuration, privacy, release-gate, or UI behavior change.

## Existing behavior

At the baseline SHA:

| Surface | Existing behavior |
|---|---|
| `scripts/tests/` | Nine test files exist. Six Python app-shell harnesses run through the `VoxPocketApp` gate, `test_testflight_schedule.py` runs through `scripts/verify --policy`, `test_testflight_packaging.rb` runs only in manual TestFlight, and `test_export_compliance.py` runs nowhere. Registration is hand-maintained. |
| TestFlight packaging contract | The release workflow rejects non-macOS releases with `iOS TestFlight releases need separate Owner authorization; only macos is allowed.` The Ruby test still expects the pre-#57 text and fails. |
| `scripts/icons/test_*.py` | The two files (16 tests at baseline) are not reached by CI. |
| `scripts/ci/tests/` | The two Python review tests run in policy. The zsh aggregate runner and its seven suites are not reached by CI. Six zsh suites pass; `orchestrator_hook_tests.sh` incorrectly requires the retired workflow and an obsolete handler contract. |
| `scripts/gates/tests/test_*.py` | Exactly three files exist: `test_local_hooks.py`, `test_private_config.py`, and `test_test_weakening.py`. `scripts/verify --policy` already executes them by unittest discovery in required policy CI. This behavior is correct. |
| `scripts/ci/kimi-review.contract.test.sh` | `scripts/verify --policy` already invokes this shell contract test directly with `bash` in required policy CI. This behavior is correct. |
| Xcode test bundles | `VoxPocketTests` and `VoxPocketUITests` are declared in `VoxPocket/project.yml` and included in the `VoxPocket` scheme. Required App CI builds but never runs the scheme test action. The non-required iOS lane tests SPM packages only. |
| Manifest executor | `scripts/test-executor/**` plus `tests/manifests/*.tests.manifest.json` are documented retained local report/orchestration tooling. Required CI comes from workflows, not the executor. The PR UI manifest selects a nonexistent `testExample`; the validator still accepts it. |
| SPM packages | Every package test target already runs in its required `SPM <package>` lane. This behavior is correct and remains unchanged. |

## User scenarios and acceptance criteria

### US1 — Release and root-script regressions fail before merge (P1)

As a maintainer, I want repository script tests to be discovered and executed by required PR CI so release-contract drift is visible before a manual release.

**Independent test**: On one PR head, the required check logs enumerate and pass the scoped Python, Ruby, and icon tests. A temporary added `scripts/tests/test_*.py` discovery canary is observed without editing a hand-maintained map, then removed before publication.

- **US1/AC1**: `scripts/tests/test_testflight_packaging.rb` asserts the exact current D-003 gate message and passes. `.github/workflows/testflight.yml` gate behavior and message are byte-for-byte unchanged.
- **US1/AC2**: A required PR check executes all nine baseline files under `scripts/tests/`; the log identifies each file or its discovered test cases, including `test_testflight_packaging.rb` and `test_export_compliance.py`.
- **US1/AC3**: Python `test_*.py` files added under `scripts/tests/` are picked up by pattern discovery without a new gate-map or workflow-list entry. Ruby `test_*.rb` files under the same directory are pattern-discovered by the required macOS PR lane with the same Fastlane Ruby environment used by TestFlight.
- **US1/AC4**: A required PR check pattern-discovers and executes both `scripts/icons/test_*.py` files and future matching files without hand registration.
- **US1/AC5**: After merge, the Owner is told to rerun manual TestFlight. Its `Test release packaging without building an App` step passes for the merged SHA. The implementation does not trigger that workflow.

### US2 — Repository governance tests stay live and correctly classified (P1)

As a maintainer, I want live zsh policy tests to block regressions while retired behavior and local-only tooling are represented honestly.

**Independent test**: `scripts/verify --policy` runs the aggregate zsh suite, test-executor syntax check, and manifest validation; the PR records the executor classification and dispatcher-retirement decision.

- **US2/AC1**: Required policy CI executes `version_tests.sh`, `changelog_tests.sh`, `trigger_tests.sh`, `release_output_tests.sh`, `release_tests.sh`, and `hook_tests.sh` through `test_runner.sh`; their existing assertions are not removed or weakened.
- **US2/AC2**: `orchestrator_hook_tests.sh` is converted from a stale positive contract into a D-002 retirement/current-handler guard: the retired workflow stays absent and the retained launcher references the live `pr-comment-handler` contract rather than the obsolete orchestrator contract. Any removed/renamed old assertion is declared in the PR's `Removed or weakened tests or policy` section with D-002 as the reason and requires explicit Owner approval before merge.
- **US2/AC3**: `test_runner.sh` pattern-discovers its zsh suite files (excluding helpers and itself), so a new matching suite is not silently orphaned. The aggregate log names every discovered suite.
- **US2/AC4**: The manifest executor is recorded as **retained local tooling, not required-PR coverage authority**. Required policy CI checks `zsh` syntax for its scripts and validates all eight manifests. The stale PR UI selector is updated to the live full `VoxPocketUITests` bundle. Required coverage does not invoke `run_pr.sh`, `run_nightly.sh`, or unsafe `link_local_dependencies.sh`.

### US3 — Xcode unit and UI bundles execute in required App CI (P1)

As a maintainer, I want the Xcode scheme's test action to run before merge so tests declared in `project.yml` cannot silently rot.

**Independent test**: The existing required `App target` check regenerates the project from `project.yml`, runs the full `VoxPocket` scheme test action on a hosted macOS UI session, and reports both test bundles.

- **US3/AC1**: Required `App target` CI runs one full-scheme macOS `xcodebuild test` with no `-only-testing` filter, and the result reports execution of both `VoxPocketTests` and `VoxPocketUITests`.
- **US3/AC2**: CI supplies no Claude/Anthropic key. The existing vision test follows its no-key path and performs no external screenshot upload. Platform-inapplicable tests may retain their existing explicit `XCTSkip`; no new skip, exclusion, disabled test, or assertion weakening is introduced to make CI pass.
- **US3/AC3**: `VoxPocket/project.yml` remains the only project-configuration source of truth. New Swift test files placed under either configured test target source directory are included by target-directory discovery, without workflow file lists. Generated `.xcodeproj` content is not edited as source.
- **US3/AC4**: The Xcode test step builds/tests only; it does not archive, install a delivery build, sign for distribution, access App Store Connect, trigger TestFlight, or authorize iOS release.
- **US3/AC5**: UI/experience manual evidence is **not applicable** because no product UI behavior changes. Automated evidence is the required App-target test log and `.xcresult` summary on the exact PR head SHA.

### US4 — The exact PR revision is deliverable (P1)

As the Owner, I want evidence bound to the exact revision so a later push cannot inherit stale approval.

- **US4/AC1**: The PR is non-draft and every currently required check is green on the same `headRefOid` named in the PR `Test evidence` section.
- **US4/AC2**: The PR body names the required lane and log evidence for Ruby packaging, export compliance, icon tests, all discovered zsh suites, the three `scripts/gates/tests/test_*.py` files, `scripts/ci/kimi-review.contract.test.sh`, manifest validation, and both Xcode bundles.
- **US4/AC3**: The PR body states existing behavior, compatibility, and removed/weakened tests. It records `none` for behavior removal except the D-002 obsolete positive-dispatcher assertions described by US2/AC2; it records no test-file deletion.
- **US4/AC4**: Required policy CI continues to execute all four already-required root tests: `scripts/gates/tests/test_local_hooks.py`, `scripts/gates/tests/test_private_config.py`, `scripts/gates/tests/test_test_weakening.py`, and `scripts/ci/kimi-review.contract.test.sh`; the exact-head required-check log names each path and shows successful execution. Extending policy coverage does not remove, narrow, skip, bypass, replace, or make any of these execution edges non-required, and D-002 does not apply to them.

## Functional requirements

- **FR-001**: Required PR CI MUST automatically discover the scoped root Python/Ruby/zsh tests described in US1 and US2.
- **FR-002**: Required App CI MUST execute the complete Xcode scheme test action as described by US3.
- **FR-003**: The implementation MUST preserve required check names and keep `quality / aggregate`, all SPM lanes, `App target`, and `Lint & policy` required.
- **FR-004**: The implementation MUST preserve SPM test behavior, package layout, TestFlight gate semantics/text, runtime app behavior, user data/configuration, and privacy/secrets boundaries.
- **FR-005**: No test file may be deleted, no test may be newly skipped/disabled/excluded, and no assertion may be weakened except the obsolete positive-dispatcher assertions covered by D-002 and US2/AC2.
- **FR-006**: CI logs MUST make discovery auditable by naming discovered files/suites and failing on an empty discovery set.
- **FR-007**: Heavy `xcodebuild` execution MUST remain CI-only; local verification uses repository-declared policy and deterministic script commands.
- **FR-008**: The PR MUST add `owner-review` because `.github/**`, `scripts/verify`, and the explicit D-002 test-contract change are important/CODEOWNERS-governed paths.

## Compatibility

- **User/runtime behavior**: No change. Recording, transcription, refinement, settings, UI, logging, telemetry, and persistence remain identical.
- **Release behavior**: No change. macOS remains the only authorized TestFlight platform; iOS TestFlight remains prohibited without separate Owner authorization.
- **API/data/config**: No public API, stored data, manifest schema, environment-variable contract, or migration changes.
- **CI contract**: Existing required check names remain stable. Those checks execute additional tests and may take longer. A newly exposed test failure is fixed in its owning layer or support scope, not bypassed.
- **Local tooling**: The manifest executor remains local-only. Policy verification adds deterministic zsh/syntax/manifest checks; heavy Xcode stays in CI.
- **Rollback**: Reverting this CI/test-coverage change restores the old coverage gap but does not require data or product rollback.

## Removed behavior

- **RB-001 (approved existing removal, D-002)**: The duplicate PR-comment dispatcher workflow remains absent. The stale zsh assertions that require that workflow and its obsolete handler contract are replaced by a retirement/current-handler invariant. The PR must declare this test-contract change and obtain Owner approval; it does not reintroduce the retired workflow.
- **No other removal is authorized**: no test file, Xcode target, scheme membership, manifest-executor file, release script, package test, current required check, or existing required-policy execution edge for the four US4/AC4 tests is removed or narrowed. D-002 authorizes only the stale orchestrator-positive replacement in RB-001.

## Edge cases

- Discovery finds zero matching files, a file cannot be imported, or a suite exits nonzero: the required check fails with the discovered path list.
- A future test has a matching name but is placed outside the contracted directories: this feature does not create the cross-repository orphan policy tracked by MY-1608; reviewers apply that separate policy.
- Fastlane Ruby is missing or its GEM path is wrong: the required packaging step fails rather than silently skipping.
- A hosted runner lacks a usable macOS UI session/signing setup: `App target` fails with the `xcodebuild` result; tests are not filtered or weakened as a workaround.
- Claude/Anthropic credentials are absent: the existing no-key path runs without network. Credentials MUST NOT be added to this PR lane.
- A platform-specific XCTest reports an existing explicit skip: the log retains the skip count/reason; the implementation may not add skips to achieve green.
- A manifest references a stale selector: the manifest repair and required policy validation must catch the known selector; required Xcode coverage remains direct workflow authority.

## Non-goals

- Building the generic shared-ci orphan-test policy (MY-1608).
- Changing SPM package tests or package architecture.
- Making the local manifest executor the source of required PR coverage, implementing quarantine/retry policy, or making nightly suites required.
- Changing product code, app UI behavior, release authorization, workflow-dispatch semantics, ruleset required-check names, or TestFlight execution.
- Running or verifying the post-merge manual TestFlight workflow on behalf of the Owner.

## Measurable outcomes

- **SC-001**: 100% of baseline test files named in Existing behavior execute through a required PR lane, or (only for existing platform-inapplicable XCTest methods) report their pre-existing explicit platform skip from a bundle that did execute.
- **SC-002**: A discovery canary proves a new `scripts/tests/test_*.py` file is executed without editing CI registration, and the canary is absent from the published tree.
- **SC-003**: Required PR logs on one head SHA show the Ruby packaging test, export-compliance tests, 16 icon tests, all discovered zsh suites, all four preserved existing root policy tests, eight validated manifests, and both Xcode test bundles.
- **SC-004**: All required checks are green on the non-draft PR head; no later push reuses earlier evidence.
- **SC-005**: After merge and Owner rerun, the manual TestFlight packaging step passes on the merged SHA.
