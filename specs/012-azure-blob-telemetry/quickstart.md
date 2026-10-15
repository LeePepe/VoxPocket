# Quickstart: Implementation and verification

Run from the repository root on the exact candidate. No command in this document provisions Azure, adds a GitHub secret, signs/uploads TestFlight, or prints a credential.

## 1. Freeze the dependency selection

Immediately before implementation publication, check whether immutable `v0.2.0` exists. If absent, use the reviewed full revision:

```text
0ffdbc82a5fbd76f54e49127b0d30a4fb8666e95
```

All three package manifests, `scripts/ci/fetch-external-deps.sh`, and `scripts/tests/test_app_logging.py` must resolve the same selection. Record the resolved 40-character revision in the PR.

From the exact shared-telemetry checkout, validate the public consumer contract:

```sh
python3 sdks/swift/scripts/external_consumer.py --revision <approved-40-character-revision>
```

## 2. Red/green privacy and lifecycle tests

Before production edits, add the contract tests named in `tasks.md` and demonstrate that current arbitrary error strings and absent Blob runtime fail the relevant new tests. Do not weaken an existing assertion to obtain green.

Focused verification after implementation:

```sh
scripts/ci/fetch-external-deps.sh
scripts/verify --layer VoxInfrastructure
scripts/verify --layer VoxApplication
scripts/verify --layer VoxPresentation
python3 scripts/ci/run_repository_tests.py app-python
scripts/verify --layer VoxPocketApp
```

The app-layer run must include disabled/invalid configuration, privacy sentinels, two typed event shapes, actor ordering, joined flush, retry retention, unchanged Loki routing, action instrumentation, and processed-plist tests.

## 3. Synthetic Release proof

Use the implementation's credential-free CI helper/lane with fake values only. It must:

1. generate the project from `VoxPocket/project.yml`;
2. build unsigned Release for macOS without archive/upload;
3. inspect the built app's processed `Info.plist`;
4. prove both keys equal the supplied synthetic values;
5. prove no literal `$(` reference remains;
6. avoid every network sender and credential log.

Then regenerate with the repository-pinned XcodeGen command and require zero uncommitted generated-project diff.

## 4. Release and repository gates

```sh
GEM_PATH="$(brew --prefix fastlane)/libexec" \
RUBY="$(brew --prefix ruby)/bin/ruby" \
  python3 scripts/ci/run_repository_tests.py packaging-ruby

scripts/verify --policy
scripts/verify
scripts/verify --all
git diff --check
```

No local signed archive, TestFlight upload, Azure request, Owner secret mutation, or workflow dispatch is part of candidate verification.

## 5. Publication evidence

Freeze one uncommitted candidate for independent content review. After exact content PASS and publication permission, commit/push/create the non-Draft important PR without changing the reviewed tree. Capture and compare:

```sh
git rev-parse HEAD
git ls-remote origin refs/heads/<task-branch>
gh pr view <pr> --json headRefOid
```

All three SHAs must match. The PR must retain the accepted Owner commands, Owner-review routing, compatibility/removed-behavior statement, dependency resolution, and the full local evidence map.

## 6. Post-merge production proof

Only after merge, Owner secret provisioning, and a fresh explicit Owner authorization may the existing manual macOS TestFlight workflow run. Team Lead records only:

- exact merged/workflow revision and run reference;
- TestFlight build number;
- blob name from a read-only listing;
- terminal result category.

Do not record the event payload, endpoint/account/container identifier, SAS value, or secret-bearing logs.
