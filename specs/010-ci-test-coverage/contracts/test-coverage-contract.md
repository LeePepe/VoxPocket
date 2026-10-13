# Test coverage contract

## Authoritative mapping

| Artifact pattern / target | Discovery | Required PR check | Required behavior |
|---|---|---|---|
| `scripts/tests/test_*.py` | root discovery CLI `app-python` | `App target` through `VoxPocketApp` gate | Execute every matched file directly; nonempty; print paths. |
| `scripts/tests/test_*.rb` | root discovery CLI `packaging-ruby` | `App target` | Execute every matched file in TestFlight-equivalent Fastlane Ruby environment; nonempty; print paths. |
| `scripts/icons/test_*.py` | root discovery CLI `icons-python` | `Lint & policy` and `quality / aggregate` | Unittest pattern discovery; nonempty; print paths. |
| `scripts/ci/tests/test_*.py` | Python unittest pattern discovery | `Lint & policy` and `quality / aggregate` | Execute all matching review tests, replacing two hand calls. |
| `scripts/ci/tests/*_tests.sh` | `test_runner.sh` sorted pattern discovery | `Lint & policy` and `quality / aggregate` | Execute all suites; exclude helper/runner; print suite paths. |
| `scripts/gates/tests/test_*.py` | Existing `python3 -m unittest discover -s scripts/gates/tests -p 'test_*.py'` policy invocation | `Lint & policy` and `quality / aggregate` | Preserve execution of all matches; baseline inventory is `test_local_hooks.py`, `test_private_config.py`, and `test_test_weakening.py`; print each path and fail on any nonzero result. |
| `scripts/ci/kimi-review.contract.test.sh` | Existing direct `bash scripts/ci/kimi-review.contract.test.sh` policy invocation | `Lint & policy` and `quality / aggregate` | Preserve direct required execution; print the exact path and fail on nonzero. |
| `scripts/test-executor/*.sh` + `scripts/perf/run_perf_suite.sh` | shell glob | `Lint & policy` and `quality / aggregate` | Syntax check only; do not run executor wrappers. |
| `tests/manifests/*.tests.manifest.json` | executor manifest discovery | `Lint & policy` and `quality / aggregate` | Validate all eight; local-tool status only. |
| `VoxPocketTests` + `VoxPocketUITests` | Xcode scheme test action generated from `VoxPocket/project.yml` | `App target` | Full macOS scheme test; no `-only-testing`; no credentials; report both bundles. |
| `Packages/*/Tests/**` | SwiftPM test targets | existing `SPM <package>` | Unchanged. |

## Discovery CLI contract

- Input is one declared group: `app-python`, `packaging-ruby`, or `icons-python`.
- Paths are resolved relative to repository root, sorted, printed, and then executed.
- Zero matches, unreadable files, spawn failure, timeout, or any child nonzero exit returns nonzero.
- The CLI does not accept arbitrary shell commands or user-home dependency paths.
- `packaging-ruby` consumes the caller's explicit Ruby/GEM environment and does not install dependencies itself.

## Xcode CI contract

- The step runs after pinned dependency fetch, Xcode selection, and `xcodegen generate --spec project.yml`.
- Command shape is full scheme `xcodebuild test` on `platform=macOS` with CI-compatible ad-hoc signing; no `-only-testing`/`-skip-testing`.
- `CLAUDE_API_KEY` and `ANTHROPIC_API_KEY` are absent.
- Evidence includes `VoxPocketTests`, `VoxPocketUITests`, pass/fail counts, existing explicit skips, `.xcresult`, and the PR head SHA.
- No archive, install, export, upload, App Store Connect, or TestFlight action is allowed.

## Removal/weakening contract

- No test file is deleted.
- D-002 permits replacing obsolete positive assertions that require the removed dispatcher workflow with retirement/current-handler assertions.
- D-002 does not authorize removing, narrowing, skipping, replacing, or making non-required the gate-test discovery or direct Kimi review-contract invocation.
- The PR lists each changed assertion/test name, reason D-002, replacement coverage, and Owner approval.
- Any other deletion, new skip, exclusion, disabled test, assertion weakening, or required-check downgrade is out of scope and blocks delivery.

## PR evidence contract

The PR body maps every row above to a required check step/log on one exact `headRefOid`. For the preserved required-policy rows, that log names `scripts/gates/tests/test_local_hooks.py`, `scripts/gates/tests/test_private_config.py`, `scripts/gates/tests/test_test_weakening.py`, and `scripts/ci/kimi-review.contract.test.sh` and shows successful execution. A later push invalidates all prior logs and review. The manifest executor's local report is supplemental and never substitutes for required workflow evidence.
