# Implementation Plan: Required PR coverage for every VoxPocket test file

**Feature**: `010-ci-test-coverage` | **Date**: 2026-10-13 | **Spec**: [`spec.md`](./spec.md)  
**Baseline**: `ea88c649ca4faca45d2265b667cc83712dbe5a68`  
**Input**: MY-1607 revision 10 and repository evidence recorded in [`research.md`](./research.md)

## Summary

Close VoxPocket's PR-time test-coverage gap without changing product or release behavior. A root-support discovery runner will execute every `scripts/tests/test_*.py` file as a script and every matching Ruby packaging test in the Fastlane Ruby environment; icon tests and live zsh suites will become required policy evidence. Existing required policy discovery for the three `scripts/gates/tests/test_*.py` files and the direct `scripts/ci/kimi-review.contract.test.sh` invocation remain required and logged. The app-layer gate will call the discovery interface instead of six hand registrations. Required `App target` CI will run the complete macOS Xcode scheme test action. The dormant manifest executor remains local-only but gains required syntax/manifest validation and a repaired full-bundle UI selector.

The stale orchestrator zsh contract follows D-002: it becomes a retirement/current-handler invariant, is declared as a changed test contract in the PR, and requires Owner approval. No test file is deleted.

## Technical context

**Languages/tooling**: Python 3.11+, zsh, Bash, Ruby/Fastlane environment, Swift 6.2/XCTest, Xcode 26/XcodeGen  
**Primary dependencies**: repository `scripts/verify`; shared-ci at `6e354f476bc53d68f0f09fc231d5cd938466af9c`; Xcode scheme generated from `VoxPocket/project.yml`  
**Storage/data**: N/A; CI logs and `.xcresult` are ephemeral evidence only  
**Testing**: direct script-file execution, Python unittest discovery for icons, zsh aggregate suites, manifest validator, full-scheme `xcodebuild test` in hosted CI  
**Target platform**: required GitHub-hosted macOS 26 PR lanes; no delivery/archive target  
**Project type**: macOS/iOS app repository with root CI/support tooling and layered Swift packages  
**Performance goal**: no explicit duration budget; avoid manifest-runner duplication/retries in required coverage  
**Constraints**: exact required check names remain stable; heavy Xcode is CI-only; no credentials in UI test lane; no TestFlight trigger; Owner approval for CODEOWNERS paths and changed obsolete assertions  
**Scope**: nine `scripts/tests` test files, two icon test files, seven zsh suites plus two Python review tests, the three existing `scripts/gates/tests/test_*.py` invocations and existing `scripts/ci/kimi-review.contract.test.sh` invocation, two Xcode test bundles, eight local executor manifests

## Constitution check — before research

| Principle / rule | Result | Plan response |
|---|---|---|
| I Immutability | PASS | No runtime object/data mutation is introduced. |
| II Layer direction | PASS | Root support owns discovery/CI; `VoxPocketApp` only consumes the discovery CLI through its gate. No package dependency changes. |
| III Concurrency safety | PASS | No production/concurrency code changes. |
| IV Privacy | PASS WITH REQUIRED GUARD | App CI provides no Claude/Anthropic key; UI screenshots remain test attachments and are never sent externally. No voice/text telemetry changes. |
| V Secrets/vendor hygiene | PASS | No secrets or private identifiers are added. Existing no-key UI path is required. |
| VI Boundary validation | PASS | Discovery fails on empty sets/failed subprocesses; manifest validation remains fail-closed. |
| Heavy Xcode in CI only | PASS | Full scheme tests run only in required `App target`; local quickstart excludes Xcode. |
| TestFlight-only delivery | PASS | Build/test only; no archive/install/upload/workflow dispatch. |
| Existing behavior preserved | PASS WITH D-002 EXCEPTION | Only obsolete positive-dispatcher assertions change, pursuant to D-002 and Owner PR approval. |

No constitutional exception is requested.

## Research decisions

The evidence and alternatives are in [`research.md`](./research.md). Binding choices:

1. **R-001**: execute `scripts/tests/test_*.py` files as standalone programs, not `unittest discover`, because six harnesses expose `main()` only.
2. **R-002**: expose root-support-owned discovery as a narrow CLI; the `VoxPocketApp` tech-context gate calls that CLI instead of maintaining six entries.
3. **R-003**: run Ruby pattern discovery in a required macOS lane with the exact TestFlight Fastlane Ruby environment; do not change the release workflow.
4. **R-004**: preserve six live zsh suites and turn the stale orchestrator contract into a D-002 retirement/current-handler guard; do not restore the retired workflow.
5. **R-005**: keep the manifest executor local-only; validate its syntax/manifests in policy and repair the stale full-UI-bundle selector. Direct required CI remains authoritative.
6. **R-006**: run one unfiltered full-scheme macOS Xcode test command in `App target`. Use an observed CI checkpoint for signing/UI-session feasibility; never filter, skip, or weaken tests to obtain green.
7. **R-008**: preserve the existing required-policy discovery of three `scripts/gates/tests/test_*.py` files and direct Kimi review-contract invocation while extending policy; exact-head logs must name all four.

## Design and interfaces

The stable inventory/lane contract is [`contracts/test-coverage-contract.md`](./contracts/test-coverage-contract.md). The conceptual records are in [`data-model.md`](./data-model.md).

### Root-support discovery CLI

Create a root-support-owned runner under `scripts/ci/` with explicit groups:

- `app-python`: sorted `scripts/tests/test_*.py`; fail if empty; print each relative path; execute every file with the repository Python.
- `packaging-ruby`: sorted `scripts/tests/test_*.rb`; fail if empty; print each path; execute every file with a caller-supplied Ruby/Fastlane environment.
- `icons-python`: use `python3 -m unittest discover -s scripts/icons -p 'test_*.py'`; print the matched source files first and fail if empty.

The runner returns nonzero on any failed child and never treats an empty glob as success. It does not discover SPM/Xcode tests or become the cross-repository MY-1608 policy.

### Architecture scope and gate edge

- `_root support` is the explicit support scope for `scripts/**`, `tests/**`, `.github/**`, and the discovery CLI; it is not a repository layer.
- `VoxPocketApp` owns `VoxPocket/tech-context.md`, `VoxPocket/project.yml`, `VoxPocketTests/**`, and `VoxPocketUITests/**`.
- T001→T003 is a support/gate contract edge through the root runner's `app-python` command. The app tech-context gate depends on that support command; it does not own its implementation.

### Required lane mapping

- `VoxPocketApp` gate / required `App target`: root runner `app-python`.
- Required macOS `App target`: root runner `packaging-ruby`, after Fastlane availability is established; complete Xcode scheme test action after XcodeGen.
- `scripts/verify --policy` / required `Lint & policy` and `quality / aggregate`: preserve existing discovery of all three `scripts/gates/tests/test_*.py` files and the direct `scripts/ci/kimi-review.contract.test.sh` invocation; add icon discovery, zsh aggregate runner, executor syntax, and eight-manifest validation alongside the other existing policy checks.
- Existing required SPM lanes: unchanged.

## Implementation slices

### Slice US1 — Root script coverage

Implement the discovery CLI and repair only the stale Ruby expected string. Switch the app layer's gate map to one `app-python` invocation; add Ruby discovery and Fastlane setup to required App CI; add icon discovery to policy. Verify each baseline path appears in logs and prove future Python discovery with a temporary canary removed before publication.

### Slice US2 — Governance suites and local-tool classification

Make `test_runner.sh` discover sorted `*_tests.sh` files, update the orchestrator suite to D-002/current-handler invariants, and run the aggregate through policy. Preserve and log the already-required three gate-test files and Kimi review-contract test while adding syntax and manifest validation. Repair the UI manifest to the full target, and record that executor wrappers remain local-only. Do not invoke its retrying PR runner as coverage evidence.

### Slice US3 — Xcode bundle coverage

Add a full unfiltered macOS scheme test step to required `App target` after dependency fetch and XcodeGen. The first draft-PR run is a bounded feasibility checkpoint: capture command, destination, signing result, both bundle names, skip count/reasons, and `.xcresult`. Test-only setup corrections may touch `VoxPocketTests/**` or `VoxPocketUITests/**`; product source changes, new skips, assertion weakening, or secret injection return to Team Lead/Planner.

### Slice US4 — Exact-head delivery evidence

Complete all repository verification, including exact-head log evidence for the four preserved root policy tests, fill every PR-template section, add `owner-review`, and bind evidence to the non-draft PR `headRefOid`. Required checks and independent content review apply to that exact SHA. After merge, hand the Owner the manual TestFlight rerun instruction; do not dispatch it.

## Verification strategy

Local/deterministic commands and evidence expectations are in [`quickstart.md`](./quickstart.md).

Fresh implementation evidence must include:

1. discovery runner path inventory and canary proof;
2. corrected Ruby packaging pass in the Fastlane environment;
3. `zsh scripts/ci/tests/test_runner.sh` with every suite named;
4. preservation/log evidence for `test_local_hooks.py`, `test_private_config.py`, `test_test_weakening.py`, and `kimi-review.contract.test.sh` in required policy;
5. executor syntax plus eight-manifest validation;
6. `scripts/verify --policy`, `scripts/verify --layer VoxPocketApp`, and `scripts/verify --all` exit 0;
7. required App-target CI log/`.xcresult` naming both Xcode bundles;
8. exact local SHA = pushed branch SHA = PR `headRefOid`, with all required checks green.

Do not claim the post-merge TestFlight result until the Owner actually reruns it.

## Acceptance traceability

| Acceptance IDs | Slice | Contract / evidence |
|---|---|---|
| US1/AC1–AC5, FR-001, FR-004, FR-006 | US1 | discovery inventory; Ruby log; unchanged TestFlight workflow diff; post-merge Owner handoff |
| US2/AC1–AC4, FR-001, FR-005, FR-006 | US2 | zsh runner log; D-002 guard; syntax/manifest logs; PR executor disposition |
| US3/AC1–AC5, FR-002, FR-004, FR-005, FR-007 | US3 | required App-target full scheme log and `.xcresult`; absence of secrets; no generated-project edit |
| US4/AC1–AC4, FR-003, FR-008 | US4 | completed PR body, four preserved root-policy-test log entries, Owner review, exact-SHA required checks |

Every acceptance criterion maps to exactly one primary slice; cross-slice dependencies are explicit in `tasks.md`.

## Project structure

```text
specs/010-ci-test-coverage/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── test-coverage-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md

.github/workflows/ci.yml                    # required lane wiring (_root support)
scripts/ci/                                 # discovery runner and governance tests (_root support)
scripts/gates/tests/                        # existing required gate tests (_root support; preserve)
scripts/tests/                              # script/packaging tests (_root support)
scripts/icons/                              # icon tests (_root support)
scripts/test-executor/                      # retained local executor (_root support)
tests/manifests/                            # local executor manifests (_root support)
VoxPocket/tech-context.md                   # VoxPocketApp gate consumer
VoxPocket/project.yml                       # XcodeGen source of truth (no change expected)
VoxPocket/VoxPocketTests/                   # unit tests; conditional repair scope only
VoxPocket/VoxPocketUITests/                 # UI tests; conditional repair scope only
```

**Structure decision**: no new product module or dependency. One root-support CLI forms the support/gate contract edge; app-layer gate/CI consumers stay thin.

## Constitution check — after design

PASS with no exception. The design keeps dependency direction unchanged, confines Xcode to CI, does not inject secrets, preserves TestFlight behavior, and gives D-002's already-removed behavior an explicit guarded/Owner-reviewed disposition. The only important-path edits (`.github/**`, `scripts/verify`, `VoxPocket/tech-context.md`) are routed through `owner-review`.

## Risks and escalation conditions

| Risk | Mitigation / escalation |
|---|---|
| Full Xcode scheme exposes stale tests or UI-session/signing failure | Use the US3 CI checkpoint. Test-only deterministic setup fixes are in scope; product changes/new skips/assertion weakening stop and return to Team Lead/Planner. |
| Root Python scripts do not conform to unittest discovery | R-001 executes each file directly and checks nonempty sorted discovery. |
| Fastlane environment increases required-lane setup | Reuse the exact TestFlight Ruby/GEM contract; failure is visible, never skipped. |
| Rewritten orchestrator assertions could hide removed checks | Preserve the suite file as a negative retirement/current-handler invariant, declare every changed assertion, cite D-002, and require Owner approval. |
| Editing the policy function could drop already-required tests | T006 preserves the gate-test discovery and direct Kimi contract edges; T010 requires exact-head logs naming all four. D-002 cannot justify changing them. |
| Manifest executor appears to provide PR authority | Contract and PR body state local-only; direct workflow evidence is authoritative. |
| Required CI duration increases | Avoid `run_pr.sh` duplication and retries; preserve existing lanes/check names. Runtime optimization may not reduce coverage. |

## Complexity tracking

No constitutional violation or new architecture complexity requires an exception.
