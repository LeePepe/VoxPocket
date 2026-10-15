# Quickstart: Implementation and verification

Run from the repository root on the exact candidate. No command in this document provisions Azure, adds a GitHub secret, signs/uploads TestFlight, or prints a credential.

## 1. Freeze the dependency selection

PR01 uses SwiftPM exact version selection everywhere:

```text
exact: "0.2.0"
```

Immediately before publication, verify annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` still peels to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`. Record both OIDs as integrity evidence only, never as a manifest revision selector or fallback. PR01 atomically updates all three package manifests, both guards, and every current authority/projection enumerated in `tasks.md` T001–T005. The old-selection search is scoped to that current-truth list; `spec.md` and `research.md` retain explicitly historical baseline evidence.

From the exact shared-telemetry checkout, validate the public consumer contract:

```sh
python3 sdks/swift/scripts/external_consumer.py --version 0.2.0
```

After reviewed PR00 lands, PR01 dependency selection, PR02 Infrastructure privacy, and PR03 Application privacy may start independently and run in parallel. This document's section order organizes verification only; it does not add dependencies. PR04 starts only after all three merge.

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

The dormant module run must include disabled/invalid configuration, isolated-`UserDefaults` proof that “Send usage data” defaults off, config alone constructs no service/identity/store, first opt-in creates/reuses a random UUID, Reset rotates it for newly admitted events, disable stops admission/upload while retaining pending files, and only a later explicit opt-in resumes. It also covers CLI/headless negative host-kind fixtures, privacy sentinels, two typed event shapes, the exact bundle initializer, coordinator-only host construction/product `track`/lifecycle `flush`, SDK-owned startup/daily heartbeat ownership, actor ordering, joined flush, retry retention, and the stored-policy SAS fixture. The adoption run proves real test-host zero service construction even with valid synthetic configuration and consent true, both macOS and cross-platform Settings wiring without Blob construction as a side effect, unchanged Loki routing, action instrumentation, and lifecycle flushes. Do not add a CLI executable solely for this proof.

The representative credential-free SAS fixture is:

```text
sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D
```

Assert exactly the accepted query names, `sr=c`, non-empty `si`/`sig`, `spr=https`, and no `sp`; reject `sp=cw`, user-delegation keys, unknown names, and invalid `sr`. A static command test proves the stored policy is created with permission `c`; no test or agent generates a real token.

For PR04, verify the changed preference layer before app verification; for PR05, verify the changed Settings layer before its app verification:

```sh
(cd Packages/VoxInfrastructure && swift build && swift test)
scripts/verify --layer VoxInfrastructure

(cd Packages/VoxPresentation && swift build && swift test)
scripts/verify --layer VoxPresentation
python3 scripts/ci/run_repository_tests.py app-python
scripts/verify --layer VoxPocketApp
```

All host-kind and credential fixtures are synthetic. Do not add or launch a CLI/headless helper merely to observe production telemetry; excluded hosts must mechanically report zero construction.

## 3. Synthetic Release proof

Use the implementation's credential-free CI helper/lane with fake values only. It must:

1. generate the project from `VoxPocket/project.yml`;
2. build unsigned Release for macOS without archive/upload;
3. inspect the built app's processed `Info.plist`;
4. prove both keys equal the supplied synthetic values;
5. prove no literal `$(` reference remains;
6. avoid every network sender and credential log.

Then regenerate with the repository-pinned XcodeGen command and require zero uncommitted generated-project diff.

## 4. TestFlight credential-path proof

Credential-free packaging fixtures must prove the production path contract without archiving or using a secret:

1. one xcconfig is created under the runner temporary directory and verified `0600`;
2. only that file path is passed via `-xcconfig`;
3. neither value appears in xcargs, command-line environment assignments, printable arguments, messages, or captured logs;
4. cleanup executes through both workflow `always` and Fastlane `ensure` on success, failure, and cancellation;
5. both raw and shell/percent-escaped synthetic sentinel forms are absent from Release-path logs;
6. manual trigger, checkout, signing, numbering, upload, tag behavior, macOS-only release, and iOS disablement remain unchanged.

## 5. Release and repository gates

```sh
GEM_PATH="$(brew --prefix fastlane)/libexec" \
RUBY="$(brew --prefix ruby)/bin/ruby" \
  python3 scripts/ci/run_repository_tests.py packaging-ruby

scripts/verify --policy
scripts/verify
scripts/verify --all
git diff --check
```

No local signed archive, TestFlight upload, Azure request, Owner secret mutation, or workflow dispatch is part of candidate verification. Run the applicable focused commands plus `scripts/verify` for every PR head; forced-full-selection PRs also require the full CI lanes and should run `scripts/verify --all` locally when practical.

## 6. Per-PR publication evidence

Freeze each PR's uncommitted candidate for independent content review. After exact content PASS and publication permission, commit/push/create that non-Draft PR without changing the reviewed tree. Capture and compare:

```sh
git rev-parse HEAD
git ls-remote origin refs/heads/<task-branch>
gh pr view <pr> --json headRefOid
```

All three SHAs must match for every PR. Each PR must retain its one goal, Owner-review routing where applicable, compatibility/removed-behavior statement, and task-local evidence. PR07 alone carries the exact placeholder Owner provisioning/secret commands from `plan.md`. After any stacked rebase/retarget, rerun verification and obtain a new exact-revision review; earlier SHA evidence is invalid.

## 7. Post-merge production proof

Only after PR01–PR07 merge, Owner creation of the permission-`c` stored access policy and compatible container service SAS, both secret writes, and a fresh explicit Owner authorization may the existing manual macOS TestFlight workflow run. The tester must then separately enable “Send usage data” in Settings and perform one approved action; Owner release authorization is not consent. Team Lead records only:

- exact merged/workflow revision and run reference;
- TestFlight build number;
- blob name from a read-only listing;
- terminal result category.

Do not record the event payload, endpoint/account/container identifier, SAS value, or secret-bearing logs.
