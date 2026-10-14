# Verification quickstart

Run from the task-owned VoxPocket checkout. Heavy Xcode verification is CI-only.

## Deterministic local verification

After implementation, run the new discovery groups and direct checks:

```sh
python3 scripts/ci/run_repository_tests.py app-python
python3 scripts/ci/run_repository_tests.py icons-python
zsh scripts/ci/tests/test_runner.sh
python3 -m unittest discover -s scripts/gates/tests -p 'test_*.py'
bash scripts/ci/kimi-review.contract.test.sh
zsh -n scripts/test-executor/*.sh scripts/perf/run_perf_suite.sh
zsh scripts/test-executor/validate_manifests.sh
```

Run the Ruby group with the same environment used by TestFlight:

```sh
GEM_PATH="$(brew --prefix fastlane)/libexec" \
RUBY="$(brew --prefix ruby)/bin/ruby" \
  python3 scripts/ci/run_repository_tests.py packaging-ruby
```

Then run repository gates:

```sh
scripts/verify --policy
scripts/verify --layer VoxPocketApp
scripts/verify --all
```

The `scripts/verify --policy` log must name and pass `scripts/gates/tests/test_local_hooks.py`, `scripts/gates/tests/test_private_config.py`, `scripts/gates/tests/test_test_weakening.py`, and `scripts/ci/kimi-review.contract.test.sh`; absence of any path is a failure even if the newly added checks pass.

## Discovery proof

Before publication, create one temporary `scripts/tests/test_discovery_canary.py` that exits 0 and emits a unique marker. Run the app-python discovery group and capture the marker/path, then remove the canary and confirm `git status --short` contains no canary. Do not commit it.

## Required CI checkpoint

The draft PR's required `App target` must run the unfiltered full macOS scheme test after XcodeGen. Capture:

- tested PR `headRefOid`;
- exact `xcodebuild test` command/destination/signing mode;
- `VoxPocketTests` and `VoxPocketUITests` in the result;
- pass/fail/skip counts and existing skip reasons;
- `.xcresult`/step-log reference;
- confirmation no Claude/Anthropic secret was provided.

Do not run local `xcodebuild`, archive, install, export, upload, or TestFlight.

## Exact-head completion

1. Capture `git rev-parse HEAD`.
2. Verify it matches the pushed remote branch and PR `headRefOid` byte-for-byte.
3. Fill every PR-template section, including Existing behavior, Compatibility, Removed or weakened tests or policy, and Test evidence.
4. Copy the required-policy log reference for all four preserved root tests into PR `Test evidence`; confirm `scripts/verify` retains their discovery/direct-invocation edges and D-002 is not claimed for them.
5. Add `owner-review`; record D-002 assertion changes and Owner approval.
6. Confirm the PR is non-draft and all required checks are green on that same SHA.
7. After merge, tell the Owner to rerun manual TestFlight. Do not trigger it.
