# Research: Required PR coverage for every VoxPocket test file

**Baseline**: `ea88c649ca4faca45d2265b667cc83712dbe5a68`  
**Date**: 2026-10-13

## R-001 — Python test discovery mode

**Evidence**: Six `scripts/tests/test_*.py` app-shell harnesses expose a `main()` guarded by `if __name__ == "__main__"` and are currently executed as standalone programs by the `VoxPocketApp` gate. `test_export_compliance.py` and `test_testflight_schedule.py` are unittest modules. Plain `python3 -m unittest discover` imports the harness files but does not call their `main()` functions.

**Decision**: discover sorted matching paths and execute each Python file directly. Fail if the set is empty and print every path before execution.

**Rejected**: converting all harnesses to unittest in this defect. That widens the change and risks altering working test semantics.

## R-002 — Support-to-layer gate seam for app Python tests

**Evidence**: `scripts/**` is `_root support`; `VoxPocket/tech-context.md` owns the `VoxPocketApp` gate and currently hand-registers six script paths.

**Decision**: `_root support` implements a narrow discovery CLI; the app-layer gate calls its `app-python` group. This preserves support/layer scope ownership while making new matching files automatic.

**Rejected**: placing discovery logic in `VoxPocket/tech-context.md` shell fragments or leaving duplicate hand lists.

## R-003 — Ruby packaging environment

**Evidence**: `test_testflight_packaging.rb` runs only in manual `.github/workflows/testflight.yml` with:

```sh
GEM_PATH="$(brew --prefix fastlane)/libexec" \
  "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb
```

Its current failure is an expected-string drift; the workflow gate text is correct.

**Decision**: reuse that exact environment in a required macOS PR lane and pattern-discover `scripts/tests/test_*.rb`. Change only the stale expected string.

**Rejected**: changing the workflow message/behavior or relying on manual TestFlight as PR evidence.

## R-004 — Legacy zsh suites

**Evidence**: `test_runner.sh` lists seven suites. Six pass and protect live release/hook scripts. `orchestrator_hook_tests.sh` alone fails because Owner commit `d8a12fbba05b2a1972ff5ec159f1239d74b54551` removed `.github/workflows/pr-comment-orchestrator.yml`; it also expects the obsolete `orchestrator.md` handler while the retained launcher references `pr-comment-handler.md`. Constitution Amendment 2026-09-20 records the retirement.

**Decision**: retain and run all suite files. Convert the stale suite to a negative workflow-retirement/current-handler guard. Make the runner discover sorted `*_tests.sh` suites and wire it into required policy. Declare changed obsolete assertions and require Owner approval.

**Rejected**:

- restoring the deleted workflow, which conflicts with D-002;
- deleting all zsh suites, which would remove live release/hook coverage;
- silently deleting the stale suite, which would violate MY-1607's weakening contract.

## R-005 — Manifest executor disposition

**Evidence**:

- README and `docs/harness/metrics-baseline.md` explicitly retain `scripts/test-executor` for local PR/nightly report generation while stating required CI comes from workflows.
- Syntax and all eight manifests validate at baseline.
- `ui.pr.tests.manifest.json` names nonexistent `VoxPocketUITests/.../testExample`.
- `run_pr.sh` retries failures, duplicates subsets of required SPM lanes, and does not cover app unit tests.
- `link_local_dependencies.sh` reads mutable user-home state and is unsafe for managed delivery workspaces.

**Decision**: classify as retained live local tooling, not dead code and not PR authority. Required policy validates zsh syntax and manifests; the UI selector becomes the stable full test target. Direct required workflow steps supply coverage evidence. Do not invoke local wrappers or dependency linker in CI.

**Rejected**: wholesale removal without an Owner decision; adopting `run_pr.sh` as the required gate.

## R-006 — Xcode unit/UI bundle disposition

**Evidence**:

- `VoxPocket/project.yml` declares `VoxPocketTests` and `VoxPocketUITests`; the `VoxPocket` scheme test action includes both.
- Required `App target` fetches pinned dependencies and regenerates XcodeGen output, but only builds.
- Existing manifest commands establish ad-hoc UI-test signing on macOS.
- The UI bundle contains real macOS launch/menu/settings/performance tests. Editor/microphone paths explicitly `XCTSkip` on macOS. The vision test returns on missing key; CI must not inject a key.

**Decision**: add one full, unfiltered macOS scheme `xcodebuild test` to required `App target`. Use the first draft-PR run as a feasibility checkpoint and capture both bundle names, existing skip reasons, signing, and `.xcresult` evidence.

**Rejected**:

- retiring either Xcode bundle;
- using the non-required iOS lane as acceptance evidence;
- filtering to a single UI test;
- adding secrets or new skips to obtain green.

## R-007 — Generic orphan policy

**Evidence**: MY-1608 owns the cross-repository shared-ci orphan-test policy.

**Decision**: keep this feature's discovery limited to the named VoxPocket directories and targets. No generic shared-ci policy or ruleset rename is included.

## R-008 — Existing required root-policy tests

**Evidence**: baseline `scripts/verify --policy` already runs unittest discovery over `scripts/gates/tests/test_*.py`, selecting `test_local_hooks.py`, `test_private_config.py`, and `test_test_weakening.py`, and directly invokes `bash scripts/ci/kimi-review.contract.test.sh`. These calls are part of required policy CI before this feature.

**Decision**: preserve both execution edges while T006 extends the policy function. Required exact-head logs name all four paths and show their successful execution. D-002 applies only to stale orchestrator-positive assertions and cannot authorize changing these tests.

**Rejected**: dropping, narrowing, skipping, replacing, or making these baseline invocations non-required because newly added policy checks still pass.
