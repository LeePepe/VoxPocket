# Telemetry consumer pilot — candidate record

Last-Reviewed: 2026-09-23

Status: the unpublished CI acquisition candidate completed exact-diff review
(Standards 0 / Spec 0 / cross-layer 0 findings) and standalone static regression
execution; positive/control checks passed and 64 negative fixtures were rejected.
This is not a workflow or native-test result. Historical narrow receipts report
25 static methods, three strict resolves, three native builds and 15 selected
Application tests passed for the declared-minimum follow-up. Their raw temporary
artifacts were lost; retained summaries are not proof this new YAML was tested.
Publication, workflow activation, PRM adoption and final acceptance remain on
hold. This is not a Dev Team/autonomy run or completion of S09, T032/T036 or full 6DQ.

## Authority and source

Existing [AGENTS](../../AGENTS.md), [constitution](../../.specify/memory/constitution.md),
[GitHub identity](../agents/github-identity.md), [local gates](../local-gates.md) and
[records map](index.md) retain authority. Detailed execution and approval
provenance stays in external retained records, not in this public record or its
link targets. Repository source links below are relative to this document. This
record supplies no public spec URL or new approval and introduces no roles,
instruction amendments or required gate.

- Consumer repository: `LeePepe/VoxPocket` (repository ID `1197276028`).
- Locally verified authoring base: `5d2ab2fafc453017f909dc289b81aead73c83918`.
- Approved provider: `https://github.com/LeePepe/shared-telemetry.git`
  (repository ID `1213460359`), root `Package.swift`.
- Exact pilot revision: `eff9c1712cd648ed0717e41183ad8bd7bf39cbea`.
  This pin is unchanged; a provider-local privacy commit is not consumed or
  validated by this pilot.
- Package identity: `shared-telemetry`; product/module/import: `LokiKit`.
  Final provider and shared-ci release pins are not established by this pilot.

All three consuming manifests must use that URL/revision and every LokiKit
product selector must name `shared-telemetry`, including the direct Application
test dependency. Preserve separate layer review/commit units, then publish only
the coherent cohort; intermediate mixed `lokikit`/`shared-telemetry` graphs are
not usable. No authored commit IDs are claimed in this record.

The compatibility repair is now expressed in the
[Infrastructure manifest](../../Packages/VoxInfrastructure/Package.swift): the
reviewed literal declaration is
`.package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.2")`,
raising the previous `1.0.0` lower bound. Application and Presentation retain
transitive use, without artificial direct dependencies. An ignored lock selection
alone cannot enforce this minimum. This declaration permits later compatible
versions; it is not an exact transitive pin or proof that all such versions work.

## Real consumer and privacy scope

[ServiceContainer](../../VoxPocket/VoxPocket/ServiceContainer.swift) already injects
telemetry into the production recording, transcription and refinement UseCases,
including macOS quick flows. Its factory selects `LokiTelemetryService` when
configured and retains `NoopTelemetryService` for Release without an endpoint.
No composition, UI, Domain or private-configuration change belongs to this slice.

The selected Application synthetic tests exercised, in both the previous
snapshot and the declared-minimum follow-up, the actual
[recording](../../Packages/VoxApplication/Sources/UseCases/DefaultRecordingUseCase.swift),
[transcription](../../Packages/VoxApplication/Sources/UseCases/DefaultTranscriptionUseCase.swift)
and [refinement](../../Packages/VoxApplication/Sources/UseCases/DefaultRefinementUseCase.swift)
implementations: numeric-duration `recording.stopped`, final-only
`transcription.completed` with editing/snapshot behavior, and refinement metrics
with preserved results, editing, errors and cancellation. Enabled, disabled and
asynchronously stalled fake sinks use in-memory collaborators and Mutex-protected
capture. These are consumer-boundary assertions, not provider transport proof or
a guarantee about arbitrary blocking synchronous `track` implementations.

The base source sends `error.localizedDescription` as free-form failure telemetry
in normal, streaming, explicit-text streaming and transcription-aware refinement.
The separate Application-owned privacy repair removes only that telemetry detail,
retaining thrown errors, UI error state, event names, metrics and cancellation.
Synthetic input/output/prompt/error-body sentinels cover leakage regressions.
The selected-test receipt below records their bounded execution, not a general
privacy PASS, provider transport proof or completed independent acceptance.

## Static consistency versus acquisition hold

[Static contract tests](../../scripts/gates/tests/test_telemetry_dependency_contract.py)
use standard-library in-memory fixtures for canonical identity, exact approved
revision in all layers, target-specific product selectors and negative cases for
local/floating/duplicate/mismatched declarations. The follow-up preserves the
original 15 cases and adds Infrastructure's canonical async-algorithms URL and
exact reviewed `from: "1.1.2"` literal contract: old `1.0.0`/`1.1.1` minimums,
missing/duplicate/local/noncanonical/alias/floating/exact/conflicting declarations
are rejected. Comments or strings cannot stand in for that declaration;
whitespace and argument order preserve meaning. Other layers must not gain an
artificial direct async-algorithms dependency. `ManifestFixtureTests` is
isolated from the real graph; `RepositoryManifestTests` reads only the three
manifests and ran only after the writers froze the cohort.
This is a narrow current-pilot literal contract, **not** general Swift evaluation,
a dependency solver or a CI gate. The earlier static snapshot passed all 15 cases
(14 fixtures plus the frozen real cohort).

The follow-up review found that nested comments and raw strings could expose fake
declarations to the scanner. The lexical repair rejects unsupported nested block
comments, Swift raw/multiline strings and unterminated forms at token boundaries;
ordinary quoted strings, escapes and supported comments retain embedded markers
without exposing calls. Negative fixtures cover both telemetry and async
declarations. Main's re-review closed that finding, rather than waiving it; the
retained review summary is **Standards 0 unresolved / Spec 0** for the scoped
candidate, not broader acceptance.

Main then executed the repaired script with SHA-256
`6fb086cd85b89919bd3a2c02e2b3710fdc8f97592d7167e6c68325d3b1fd38af`:
**25 methods passed in 0.110s**, all `OK`, zero failures, exit zero. These comprise
24 in-memory fixture methods and one real-manifest-cohort method; subtests are
not additional methods. Script and manifest hashes matched after execution.
Neither class is installed in CI/hooks; this result establishes only the narrow
literal contract, not general Swift validity or dependency acquisition.

The unpublished acquisition candidate removes the redundant LokiKit checkout
from [ci.yml](../../.github/workflows/ci.yml)'s `spm` job and from
[testflight.yml](../../.github/workflows/testflight.yml)'s `release` job. The `app`
job retains exactly one fixture checkout at `path: LokiKit`, now using
`LeePepe/shared-telemetry` at `eff9c1712cd648ed0717e41183ad8bd7bf39cbea`.
The unchanged [logging regression](../../scripts/tests/test_app_logging.py) needs
that sibling path. This fixture does not supply the runtime URL dependency:
matching the three unchanged manifests establishes source-pin coherence only,
not shared resolution or complete transitive reproducibility.

A standalone [Ruby contract](../../scripts/tests/test_ci_telemetry_acquisition.rb)
passed isolated execution and remains uninstalled in CI/hooks. It embeds
hash-rooted pre-edit YAML, validates Psych AST structure without YAML object
loading, and permits only
the specified checkout/comment changes. It covers checkout cardinality, exact
repository/path/pin, frozen manifests and logging harness, unchanged control
structures, and in-memory negative fixtures. Independent exact-diff review found
no Standards, Spec or cross-layer findings. After static execution-isolation
review, the following command ran from the worktree with exit zero:

```sh
/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C /usr/bin/ruby --disable-gems scripts/tests/test_ci_telemetry_acquisition.rb
```

Observed output: `OK: frozen workflows, checkout/pin/consumer contracts; 64 negative fixtures`.
Positive/control checks passed and all 64 negative fixtures were rejected; these
are static in-memory fixtures, not native or CI tests. The script does not execute
embedded workflow commands or acquire dependencies. This result does not clear
the activation/publication hold or extend historical native evidence.
Existing required names, events, matrices, permissions, commands,
AppleUITesting acquisition and signing controls
are preserved. macOS release remains manual-only; iOS release remains paused.
No workflow run, CI installation/green result, activation or publication is claimed;
even a draft PR remains held because it can trigger acquisition.

## Bounded verification evidence and remaining limits

The original async-algorithms **1.1.1** native build failed Swift **6.4**
RegionIsolation checking. The observed compiler was `swiftlang-6.4.0.34.1` with
the **macOS 27 SDK**; these artifacts do not establish an exact Xcode marketing or
build number. [Upstream PR #399](https://github.com/apple/swift-async-algorithms/pull/399)
fixes the relevant sending/isolation defect and is included in
[release 1.1.2](https://github.com/apple/swift-async-algorithms/releases/tag/1.1.2).
The diagnosis initially proposed an experiment; subsequent bounded receipts
established the following results for the previous candidate snapshot:

- **Three strict resolves and three native builds passed**: Infrastructure,
  Application and Presentation, with async-algorithms **1.1.2**, revision
  `2971dd5d9f6e0515664b01044826bcea16e59fac`. The other ten pins stayed unchanged;
  inspected source revisions, active manifests, dependency edges and pin maps
  reconciled. Containment audits passed.
- The native-build receipt initially held test launch for runner provenance
  adjudication, with zero tests launched. A later selected-test receipt records
  one controlled XCTest invocation: **15 named tests passed**, comprising
  `UseCasesTests` **5**, `DefaultRefinementUseCaseTests` **8** and
  `TelemetryConsumerTests` **2**, with no extra, skipped or failed cases. XCTest
  exited zero; runner integrity and the observation discrepancies were reconciled.
- The earlier static contract receipt separately records **15 cases passed**.
  Static cases and selected native tests are different evidence sets.

The three `Package.resolved` files were **proposed inputs later validated** by
strict resolution, not generated resolver outputs. Their shared validated digest
was `184de672a65cbee393978e1d0da87ae1f65dc87b764f91094c4f371beefc0a59`.
They were ignored transitive inputs, not a published lockfile policy. All three
are absent after recovery and are not reconstructed by this acquisition slice. The
provider's TelemetryDeck range remains `>=2.0.0, <3.0.0`; the provider revision
alone does not make transitive resolution reproducible.

Those historical receipts predate the Infrastructure lower-bound declaration
and static regression extension. Separate follow-up verification has now passed
against the declared-minimum Infrastructure manifest with SHA-256
`38d81441f007cd39e641a7dfd0942622644b1141d3ad89c7def828fe1b0ce8bf`:

- **Three strict resolves and three native builds passed**, once per root:
  Infrastructure, Application and Presentation. Audits passed and no compiler
  failure occurred.
- **15 selected Application cases passed in one invocation**: `UseCasesTests`
  **5**, `DefaultRefinementUseCaseTests` **8**, `TelemetryConsumerTests` **2**;
  zero failed, skipped or extra cases.
- All **11 pins** stayed unchanged and dependency edges reconciled, including
  the new `1.1.2` minimum. The three proposed lock inputs, prior runs and evidence
  were preserved; this does not introduce a published lock policy.

These are actual isolated candidate results recorded separately from the static
execution. Detailed review and execution receipts remain in external retained
records. The acquisition candidate does not rerun or extend that historical
evidence; lost raw temporary artifacts cannot be revalidated from those summaries.

Affected-package builds and selected synthetic tests do not establish full layer
suite results or required App/compatibility CI. CI currently selects latest Xcode,
so fixed-toolchain reproducibility is not established; the observed Swift 6.4 /
macOS 27 SDK does not amend the documented toolchain policy. No local App
build/archive, installation, live runtime/model/microphone execution or TestFlight
dispatch is established by these receipts or authorized by this follow-up.

Transport remains open: the baseline real Loki service uses `URLSession.shared`
and default Application Support storage, so disabled telemetry is not isolation.
Async recording flush, termination draining, retry/loss and authenticated receipt
need separate provider/lifecycle evidence; fake sinks cannot establish delivery.

## Rollback and remaining delivery

Source rollback must restore the coherent three-manifest consumer/acquisition
unit together, preserving the separate privacy repair's explicit disposition.
Reproducible dependency rollback additionally requires known-good validated
resolution inputs; restoring an unpinned sibling path alone cannot provide it.
No user data migration is needed. Preserve unrelated work, private files, caches
and App artifacts; do not discard unpublished pilot changes or retained evidence.

Still pending: approved instruction/hook reconciliation (including stale sibling
paths); acquisition activation and publication authorization;
final telemetry SDK/provider and shared-ci pins; existing issue/PRM routing;
real transport/lifecycle delivery and recovery evidence; full 6DQ and full-goal
acceptance. Hooks and instructions are unchanged; the CI edits are unpublished
candidate source only and no new gate is activated. PRM adoption, PR publication
and merge remain on hold under existing authority. No new VoxPocket commit/PR,
CI run, merge, release, final SDK pin or transport PASS is claimed.
