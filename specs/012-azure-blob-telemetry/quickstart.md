# Quickstart: Implementation and verification

Run from the repository root on the exact candidate. No command in this document provisions Azure, adds a GitHub secret, signs/uploads TestFlight, or prints a credential.

## 1. Land the ordered CI → runtime → dependency safety chain

PR01 changes only `.github/workflows/ci.yml` to run the existing macOS `VoxPocketTests` target after XcodeGen with signing disabled. Verify the current suite and repository gates pass before proceeding.

PR02, still on the old shared-telemetry version, introduces the shared dedicated serial non-main coordinator. From an `@MainActor` test, submit `track A`, `track B`, then await `flush`; the underlying factory/spy must record `construct → A → B → flush`, maximum concurrency one, and `Thread.isMainThread == false` for every operation. A structural regression must find no raw-provider bypass, and PR01's required CI must execute the test.

PR03 then uses SwiftPM exact version selection everywhere:

```text
exact: "0.2.0"
```

Immediately before publication, verify annotated tag object `8d85333eb3c039378f116f082d0f59b0b08207a5` still peels to `903f4b9bc01cfcfeba3ce96e13519d841781b40a`. Record both OIDs as integrity evidence only, never as a manifest revision selector or fallback. PR03 atomically updates all three package manifests, both guards, and every current exact-version authority/projection enumerated in `tasks.md` T002–T004/T013. It contains no runtime source/test adaptation or required-CI wiring. The old-selection search is scoped to that current-truth list; `spec.md` and `research.md` retain explicitly historical baseline evidence.

From the exact shared-telemetry checkout, validate the public consumer contract:

```sh
python3 sdks/swift/scripts/external_consumer.py --version 0.2.0
```

After reviewed PR00 lands, the ordered PR01→PR02→PR03 safety chain and the independent PR04/PR05 privacy repairs may proceed in parallel. PR06 starts only after PR03–PR05 merge.

Do not pass `maxDiskBytes` to either legacy Loki or future Blob construction. The accepted pinned-provider default is 50 MiB of persisted source JSON plus Blob sidecars, with whole-oldest-batch eviction, oversized-event rejection, and durable loss accounting. Before a rollback, stop producers, prevent old/new writer overlap, make storage writable, and finish pending paired eviction cleanup with the `0.2.0` capacity-aware reader; preserve its ledger and retained files. Already evicted events are unrecoverable. These are intentional migration semantics, not a provider test copied into VoxPocket.

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

The dormant module run must include disabled/invalid configuration and isolated-`UserDefaults` proof that “Send usage data” defaults off. With valid configuration before first opt-in, prove it constructs no Blob service/store, creates no identity, and never invokes the identity provider. Separately, exercise missing/empty/unexpanded configuration independently of consent history, explicitly including a previous-opt-in state with a retained UUID, and prove zero identity creation, identity-provider calls, store creation/opening/access, enqueue calls, and network calls. First opt-in creates one random UUID; disable stops admission/upload without host/manual deletion while retaining non-evicted pending files, the capacity ledger, and that persisted UUID without active-service identity use; every later explicit opt-in and eligible launch reuses that same UUID for the app installation's lifetime. Prove v1 has no install-ID Reset/rotation surface, requires no shared-telemetry API change, and performs no host parsing of adapter-private storage or catalog state. The run also covers CLI/headless negative host-kind fixtures, privacy sentinels, two typed event shapes, provider-default bundle construction with no `maxDiskBytes` argument, coordinator-only host construction/product `track`/lifecycle `flush`, SDK-owned startup/daily heartbeat ownership, ordering, joined flush, non-evicted retryability, and the stored-policy SAS fixture. The adoption run proves real test-host zero Blob construction even with valid synthetic configuration and consent true, both macOS and cross-platform Settings wiring without Blob construction as a side effect, preserved PR02 coordinator/PR03 default-capacity behavior, action instrumentation, and lifecycle flushes. Do not add a CLI executable solely for this proof.

The representative credential-free SAS fixture is:

```text
sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D
```

Assert exactly the accepted query names, `sr=c`, non-empty `si`/`sig`, `spr=https`, and no `sp`; reject `sp=cw`, user-delegation keys, unknown names, and invalid `sr`. A static command test proves the stored policy is created with permission `c`; no test or agent generates a real token.

For PR06, verify the changed preference layer before app verification; for PR07, verify the changed Settings layer before its app verification:

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

All three SHAs must match for every PR. Each PR must retain its one goal, Owner-review routing where applicable, compatibility/removed-behavior statement, and task-local evidence. PR09 alone carries the exact placeholder Owner provisioning/secret commands from `plan.md`. After any stacked rebase/retarget, rerun verification and obtain a new exact-revision review; earlier SHA evidence is invalid.

## 7. Post-merge production proof

Only after PR01–PR09 merge, Owner creation of the permission-`c` stored access policy and compatible container service SAS, both secret writes, and a fresh explicit Owner authorization may the existing manual macOS TestFlight workflow run. The tester must then separately enable “Send usage data” in Settings and perform one approved action; Owner release authorization is not consent. Team Lead records only:

- exact merged/workflow revision and run reference;
- TestFlight build number;
- blob name from a read-only listing;
- terminal result category.

Do not record the event payload, endpoint/account/container identifier, SAS value, or secret-bearing logs.
