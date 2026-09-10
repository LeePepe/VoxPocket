# Implementation Plan: MY-1540 RepoInfra Recovery and Logging Delivery

**Branch**: `agent/planner-lead/61b8ffb64655` | **Date**: 2026-09-10 | **Spec**: [spec.md](./spec.md)

**Input**: MY-1540 owner authorization and the existing logging candidate in PR #35.

## Summary

Deliver the already-implemented VoxPocket logging integration by first proving current-Mac Dev Team runtime ownership, diagnosing the required Codex review failure in the self-hosted runner's real service context, and applying and independently reviewing the smallest reversible RepoInfra repair. Bootstrap the existing NAS-bound MY-1540 observer through a catalog-valid configuration and one successful probe; do not create another scheduler. Adopt external PR #35 into the normal delivery workflow, and ship a separate privacy-safe TranscriptionKit production-adapter benchmark harness through its own reviewed PR. After both revisions merge, hand exact evidence to the root coordinator for private benchmark execution, candidate log validation, a fresh `main` archive, reversible `/Applications` replacement, and real-app Loki/Grafana privacy acceptance.

The design uses one operational recovery seam with a compact evidence contract. Runtime ownership, host configuration, repository review logic, existing-autopilot control, external-PR adoption, GitHub delivery, benchmark execution, local installation, and telemetry observation are adapters behind that seam. The only product-layer change is a separate test-harness slice in the existing VoxInfrastructure/TranscriptionKit layer; no new architecture layer or logging implementation is introduced.

## Technical Context

**Language/Version**: Bash and GitHub Actions YAML for the review control plane; macOS `launchd`; Swift 6.2/Xcode only for the already-existing app build and tests

**Primary Dependencies**: Multica runtimes/autopilots, GitHub Actions self-hosted runner, Codex CLI with isolated `CODEX_HOME`, GitHub CLI, macOS launch services, Apple Speech, the existing configured Azure speech service, WhisperKit base and large-v3-turbo, existing LokiKit local Compose stack, protected-branch auto-merge

**Storage**: Existing runner/review configuration and adjacent timestamped backups; benchmark input/full-text output remain only under the protected app-sandbox benchmark directory; new archive and installed-app backup remain local and are recorded in the handoff

**Testing**: Runtime-ID/daemon proof, one existing-autopilot probe, same-service-context redacted probes, isolated failure/recovery exercise, repository policy checks for tracked repairs, exact-head required CI, serial production-adapter benchmark runs, fresh Debug archive validation, process-count check, time-bounded Loki query, Grafana readiness, and privacy field inspection

**Target Platform**: The registered `[self-hosted, macOS, ARM64]` VoxPocket runner on the owner's mobile Mac, followed by the local macOS VoxPocket installation

**Project Type**: Operational recovery and delivery; existing desktop application implementation is consumed but not redesigned

**Performance Goals**: An isolated unavailable condition produces an explicit diagnosis within 120 seconds; accepted app records appear within a five-minute query window

**Constraints**: No global proxy/network changes; no new endpoint, credential, provider, model, or authentication choice beyond the approved observer catalog selection and existing Azure speech service; no secret/config-content/private fixture capture; no product UI/default-model changes; no weakened gate, synthetic status, direct protected-branch push, force-push, admin merge, or hook bypass; root coordinator exclusively owns the primary checkout and final install

**Scale/Scope**: Two current-Mac Dev Team runtimes, one NAS observer runtime, one existing autopilot/trigger, one runner service, one isolated Codex review home, one existing PR (#35), one separate benchmark PR, one 16.213-second private fixture, one macOS Debug archive, one installed app, and one local Loki/Grafana stack

## Constitution Check

### Pre-research gate

| Principle | Result | Evidence |
|---|---|---|
| I. Immutability | PASS | Operational changes use backups/replacement; benchmark result values are immutable records passed to a private report sink. |
| II. Layered Dependency Direction | PASS | RepoInfra remains external/control-plane scope. Benchmark code stays in existing VoxInfrastructure/TranscriptionKit and does not add reverse dependencies. |
| III. Concurrency Safety | PASS | Review failure handling remains outside the app main thread; benchmark injection preserves actor/sendability rules and runs serially. |
| IV. Privacy of Voice & Text | PASS | Diagnostics redact secrets/content; benchmark full text remains in the protected sandbox directory; log acceptance uses startup/window actions and forbids voice recording/content telemetry. |
| V. Secrets & External-Vendor Hygiene | PASS | Existing review/config homes are preserved; benchmark uses only the existing configured Azure speech service; credentials/endpoints are never committed, copied into evidence, or invented. |
| VI. Input Validation at Boundaries | PASS | Exact SHA, service-context probe results, archive identity, process state, and Loki records are validated before promotion. |

### Post-design gate

PASS. The contracts make evidence and ordering explicit, the repair remains reversible and fail-closed, and RepoInfra changes remain isolated. The approved benchmark is a separate, reviewed VoxInfrastructure/TranscriptionKit test-harness slice with no UI/default-model change. Any repository repair is limited to the named review files and must use its own protected-branch PR.

## Architecture and Seam Decision

### Module

The **RepoInfra Recovery** module owns one interface: produce a redacted `RecoveryEvidence` record that establishes the exact candidate, diagnosis, reversible repair, recovery proof, gate result, merge result, install handoff, and acceptance result.

This interface hides five adapters:

1. **Runtime ownership adapter** — current-Mac Codex/Copilot role bindings and explicit legacy-daemon exclusion.
2. **Runner adapter** — the LaunchAgent and `/Users/tianpli/actions-runner/` runtime.
3. **Review adapter** — `/Users/tianpli/.codex-review/`, `scripts/ci/codex-review.sh`, and `.github/workflows/codex-review-target.yml`.
4. **Supervisor adapter** — the existing NAS-bound observer agent, autopilot, and disabled schedule trigger.
5. **GitHub delivery adapter** — external PR adoption, required checks, auto-merge, PR #35, and remote `main`.
6. **Benchmark adapter** — the production TranscriptionKit file/buffer seam, private fixture/report store, and sanitized numeric summary.
7. **Local delivery adapter** — the root coordinator's primary checkout, archive, `/Applications/VoxPocket.app`, and app backup.
8. **Telemetry acceptance adapter** — the existing LokiKit stack, Loki query surface, and Grafana dashboard.

The external seam is the structured handoff in [contracts/recovery-evidence.md](./contracts/recovery-evidence.md). Tests and operators validate observable outcomes through this seam. Internal service/config details are not copied into the interface.

### Decision gates

- **D0 Runtime ownership**: Record exact role/runtime/daemon IDs; any Dev Team role on the legacy daemon blocks dispatch.
- **D1 Diagnosis**: Advance only when evidence supports a falsifiable root cause and exact repair target. Otherwise escalate the precise owner-dependent choice.
- **D2 Repair scope**: Prefer a host-only repair when the defect is host configuration. If the defect is in tracked review logic, use only `.github/workflows/codex-review-target.yml`, `scripts/ci/codex-review.sh`, and narrow tests under `scripts/ci/tests/`; do not edit PR #35's logging implementation.
- **D3 Independent review**: No repaired configuration or revision may be used for shipping until an independent reviewer passes its exact digest or commit.
- **D4 Supervisor bootstrap**: Inspect the NAS runtime catalog, configure only the existing observer, run exactly one successful probe, then enable only the existing trigger.
- **D5 External PR adoption**: Team Lead records repository/workspace/head/base/scope/evidence before PR Manager acts. If a tracked repair landed on `main`, refresh PR #35 first and recapture its head.
- **D6 Shipping**: Rerun only the real required gate for the current exact head, then require every required check and GitHub's merged state.
- **D7 Benchmark**: Ship the harness separately, then run only from the protected current-Mac fixture path; private text never crosses into public evidence.
- **D8 Installation**: The root coordinator proceeds only after both PRs merge, candidate validation passes, and the pre-install human-state check is clear; failure restores the app backup.
- **D9 Acceptance**: Delivery completes only when benchmark evidence, real installed-app events, privacy inspection, and final schedule disablement all pass.

## Project Structure

### Documentation (this feature)

```text
specs/005-my-1540-recovery/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
├── checklists/
│   └── requirements.md
└── contracts/
    └── recovery-evidence.md
```

### Existing repository and operational surfaces

```text
.github/workflows/codex-review-target.yml       # trusted required-review workflow
scripts/ci/codex-review.sh                      # fail-closed Codex review entry point
scripts/ci/tests/test_codex_review_preflight.sh # only if diagnosis requires tracked failure-path tests
scripts/ci/tests/test_runner.sh                  # register a tracked review test when selected
scripts/rulesets/main-protection.json           # read-only required-check contract
VoxPocket/VoxPocket/                            # existing PR #35 app shell; no new implementation here
scripts/tests/test_app_logging.py                # existing PR #35 logging harness
docker/telemetry/README.md                       # existing PR #35 local-stack/operator guidance

Packages/VoxInfrastructure/Sources/TranscriptionKit/DefaultAppleSpeechRequestFactory.swift
                                                 # shared Apple request policy; URL variant only if required
Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift
                                                 # internal/testable engine injection and quiet benchmark config only
Packages/VoxInfrastructure/Tests/PrivateTranscriptionBenchmarkTests/
├── ApprovedOwnerBenchmarkTests.swift
├── BenchmarkAudioFixture.swift
├── ProductionRecognitionAdapters.swift
├── ProductionAdapterSeamTests.swift
├── BenchmarkMetricsAndScoring.swift
├── PrivateBenchmarkReportWriter.swift
└── SilentBenchmarkLogger.swift
Packages/VoxInfrastructure/Package.swift         # dedicated test-target wiring

/Users/tianpli/actions-runner/                   # VoxPocket runner runtime; no unrelated runner edits
/Users/tianpli/Library/LaunchAgents/
  actions.runner.LeePepe-VoxPocket.macmini-local.plist
/Users/tianpli/.codex-review/                    # isolated review home; redact secrets/config contents
/Users/tianpli/Library/Containers/com.leepepe.voxpocket/Data/Library/Application Support/VoxPocket/benchmarks/owner-20260910/
                                                 # owner fixture and all full-text benchmark outputs
/Applications/VoxPocket.app                     # installed app; root coordinator only
/Users/tianpli/Development/VoxPocket/            # primary checkout; root coordinator only
/Users/tianpli/Development/LokiKit/              # published dependency + local telemetry stack

Multica control-plane objects:
- current-Mac daemon: 019fd055-0738-723e-a556-762fc863b720
- current-Mac Codex runtime: ab653716-b90e-40f1-b6ff-5095f818a1f8
- current-Mac Copilot runtime: 05eda9df-e582-43e1-b8e0-3c16f847522d
- legacy excluded daemon: 019e2a6c-e1d4-737a-afca-e945ec0c8137
- observer/autopilot/runtime/trigger: efc285c0-5c91-4055-80ba-e64b9d6419f9 / d67e7307-d0ef-40c4-a597-fd48d73cda48 / a06e54f0-65cf-46ea-96de-97da512438cf / 52310b59-fd61-4cf7-ae14-523ae55d2a26
```

**Structure Decision**: Planning artifacts live in `specs/005-my-1540-recovery/`. Operational recovery owns top-level RepoInfra only; no `RepoInfra/` product directory or package is invented. A diagnosis spike chooses between the named host paths and tracked review files. The benchmark is a dedicated existing-layer test target that composes production request/engine/merger/refinement adapters through `@testable` access; it does not refactor the four microphone-bound coordinators. App-shell files from PR #35, all other `Packages/**`, LokiKit source, global network settings, unrelated runners, shared agents, private fixture data, and the user's primary checkout are excluded from repair/harness implementation.

## Delivery Slices

| Slice | Outcome | Depends on | Exit evidence |
|---|---|---|---|
| US1 Recover runner | Current-Mac ownership proved; one falsifiable runner cause and reversible repair verified | None | Runtime map, redacted hypothesis matrix, repair review, failure/recovery proof |
| US2 Bootstrap observer | Existing NAS observer succeeds and existing schedule is enabled | US1 | Catalog evidence, exact agent config, successful probe run, trigger state |
| US3 Adopt and ship PR #35 | External candidate is formally adopted; exact head gets required PASS and merges | US2 | Workspace metadata, check URLs, PR head and merge SHA |
| US4 Benchmark adapters | Separate reviewed TranscriptionKit harness produces private full results and public numeric summary | US3 | Harness merge SHA, six-run groups, timing/accuracy metrics, privacy proof |
| US5 Build and install | Root coordinator validates candidates; fresh final-main archive replaces old app safely | US3 + US4 | Candidate log proof, source/dependency SHAs, archive/app/backup paths, one-process proof |
| US6 Accept and close | Installed app emits private-safe logs; delivery evidence is complete; observer schedule stops | US5 | Exact query/window/count, dashboard readiness, privacy inspection, rollback and schedule state |

## Repair Decision Table

| Supported root cause | Authorized repair target | Required backup/rollback | Exclusions |
|---|---|---|---|
| Runner/LaunchAgent lifecycle or environment | `/Users/tianpli/Library/LaunchAgents/actions.runner.LeePepe-VoxPocket.macmini-local.plist` and VoxPocket service state | Copy the original plist with timestamp and checksum; restore it and reload the same label | No other runner, daemon, or global network setting |
| Isolated Codex review configuration | The minimum file(s) under `/Users/tianpli/.codex-review/` identified by diagnosis | Copy each changed file with timestamp and checksum; restore exact copies | Never expose tokens/config contents; do not touch `~/.codex` Raven setup |
| Tracked review bootstrap/diagnostics defect | `.github/workflows/codex-review-target.yml`, `scripts/ci/codex-review.sh`, optional `scripts/ci/tests/test_codex_review_preflight.sh` | Revert through a normal PR; retain existing 25-minute outer timeout and fail-closed exit | No logging/product files, ruleset weakening, gate rename, or untrusted PR execution |
| Missing or changed provider endpoint/credential/model/auth | No repair target | Escalate exact missing decision to owner | Never invent or copy credentials, endpoints, providers, or models |

## Verification Strategy

### US1 — current-Mac runner diagnosis and repair

- Capture exact Dev Team role/runtime/daemon IDs and show zero role bindings to the legacy daemon before dispatch.
- Pin PR #35's live head and base before probing.
- Record runner label/service state separately from endpoint reachability.
- Run redacted TCP/TLS and authenticated review-path probes in the same service context used by the runner; interactive-shell results are comparison evidence only.
- Test each alternative hypothesis and record contradicting evidence; do not print environment values, credential files, request bodies, or user content.
- Capture checksums and timestamped backups before any host edit.
- Prove failure within 120 seconds with an isolated per-process or test-adapter disconnect; never change the machine's global connection.
- Restore connectivity and prove the same interface recovers.
- For tracked changes, run the focused review preflight test plus repository policy checks and ship the repair through a separately reviewed PR to `main`.

### US2 — existing-autopilot bootstrap

- Confirm the existing observer remains on NAS runtime `a06e54f0-65cf-46ea-96de-97da512438cf` and its existing schedule is disabled.
- Record its two failed run IDs and the sanitized unsupported-default-model error.
- Inspect the NAS runtime's supported catalog without trial-and-error mutations; select one valid model/effort/service-tier tuple.
- Update only observer agent `efc285c0-5c91-4055-80ba-e64b9d6419f9`, run exactly one authorized probe, and verify its output respects the observe/dispatch/bounded-rerun/report boundary.
- Enable only trigger `52310b59-fd61-4cf7-ae14-523ae55d2a26` on `*/10 * * * *` after the probe succeeds.

### US3 — external PR adoption and shipping

- Team Lead records MY-1540, repository, isolated delivery workspace, base SHA, branch, exact PR #35 head/base, scope, and existing evidence before PR Manager supervision.
- If tracked RepoInfra repair landed on `main`, refresh PR #35 onto that trusted base and recapture the changed head SHA.
- Independently review the current exact PR #35 head; Kimi remains advisory.
- Obtain a real `codex-review-target` PASS and require all eight contexts in `scripts/rulesets/main-protection.json` on that same head.
- Let existing auto-squash merge execute; confirm `state=MERGED`, `mergedAt`, merge SHA, and remote-main containment.

### US4 — production-adapter benchmark harness and run

- Add a dedicated `PrivateTranscriptionBenchmarkTests` test target. Compose the production Apple request factory, Azure `WhisperEngine`, internal local Whisper engine, `mergedTranscription`, and production LLM/refinement adapters; do not refactor the four microphone-bound coordinators.
- Decode once to canonical mono PCM/WAV inside the protected directory. Feed the exact canonical file to Azure/local batch adapters and identical buffers serially at 1x to Apple and applicable hybrid paths.
- If needed, factor only common Apple request policy into a URL-request variant and expose only the minimal internal/testable WhisperKit engine preparation/file-or-buffer seam. Record Apple's requested mode as `automatic`, `supportsOnDeviceRecognition` as capability, and `actual_route=unknown` unless the framework proves routing.
- Inject `SilentBenchmarkLogger` and no-op telemetry into every benchmark adapter, merger, and refinement path. Force WhisperKit benchmark configuration to `verbose=false`/no logging. Do not weaken production error handling or assert private strings in test failures.
- Validate manifest/root/file containment with symlink rejection and owner-only permissions; unit-test serial run planning, timing boundaries, normalization/scoring, output redaction, and unavailable/no-fallback classification.
- Run `swift build --package-path Packages/VoxInfrastructure` and `swift test --package-path Packages/VoxInfrastructure`; no `xcodebuild` is allowed for this Packages-only diff.
- Ship the harness in its own independently reviewed PR and capture its merge SHA.
- On the current Mac only, validate the owner-only manifest and execute identical decoded audio serially: one cold and five warm runs for each supported group and applicable batch/16.213-second real-time-paced mode.
- Verify the Azure deployment from loaded private configuration without exposing it; if underlying deployed model/version is unobservable, say so instead of inferring from an alias. Cloud hybrid has merger `N/A` where production intentionally skips it; local hybrid reports merger/refinement separately.
- Keep full reference/recognized text and private filenames in `results/<UTC>-<git-sha>/private-report.json` under the protected benchmark directory. Publish only individual numeric runs, median/min/max, approved labels, unavailable/unknown classifications, `test` preservation, and the case-specific recommendation.

### US5 — candidate validation, final archive, and installation

- Root coordinator alone synchronizes `/Users/tianpli/Development/VoxPocket/` with latest remote `main`, preserving unrelated untracked paths and recording local cleanliness.
- Before replacement, run the candidate archive outside `/Applications`, prove the safe startup marker reaches the application-log stream, and retain the old installed app/data unchanged.
- Record final `main` SHA, PR #35 merge SHA, benchmark merge SHA, and published LokiKit SHA.
- Run the repository-defined macOS Debug archive command with a new timestamped archive path; retain existing archives.
- Verify the archive contains `Products/Applications/VoxPocket.app` and the private-configuration bundle guard passes.
- Verify with the owner that the old app is not recording and has no unsaved text; record consent state without content.
- Back up `/Applications/VoxPocket.app`, gracefully quit it, replace it, reopen once, and verify one running instance.
- On failure, move only the failed replacement aside, restore the exact backup, and reopen only if it was running before.

### US6 — installed-app acceptance and closeout

- Check the Loki/Grafana stack on loopback, launch the installed app, and perform one harmless window show/hide operation.
- Query `{app="VoxPocket",stream="log"}` for an exact five-minute window and record the query, UTC bounds, result count, and representative fixed messages.
- Verify Grafana dashboard readiness at `/d/voxpocket-logs`.
- Inspect all returned message/context values for forbidden transcript, prompt, refined text, credential, and arbitrary error-body content. A redaction placeholder is acceptable; dynamic content is not.
- Do not use microphone/voice and do not substitute a library smoke test for real-app evidence.
- Deliver the full evidence contract, then disable the task-specific observer schedule and record the disabled state.

## Risks and Mitigations

| Risk | Mitigation / stop condition |
|---|---|
| SwiftPM test process lacks Speech/TCC authorization for Apple Speech | Preflight authorization in the current-Mac session. If the production request adapter cannot run in the approved test host, report Apple/hybrid groups unavailable and return a narrowly scoped harness-host decision; do not use microphone replay or relabel another provider. |
| Apple on-device/server route is not observable | Record `requested_mode=automatic`, device capability, and `actual_route=unknown`; never infer routing from capability or latency. |
| Azure deployment alias hides the real deployed model/version | Read only through the approved private-config loader and report the observable deployment label; if provider metadata cannot prove the underlying model, mark it unobservable. |
| Tracked review repair is placed only on PR #35 | Merge the repair PR to trusted `main` first, then refresh PR #35 so `pull_request_target` uses the repaired base. |
| Private benchmark text leaks through legacy logs or test failures | Inject silent logger/no-op telemetry, disable WhisperKit verbosity, emit stable error codes, scan stdout/summary, and keep full text only in the protected results directory. |
| Shared model caches or primary checkout are altered during benchmark/build | Use task-local build artifacts, never delete global caches, preserve/report unrelated untracked paths, and give primary-checkout ownership only to root coordinator. |
| Observer probe dispatches or mutates beyond its role | Independently review exact agent configuration and scope; run one probe with the schedule disabled; do not enable on any scope violation. |

## Rollback and Recovery

- **Host repair**: Stop only the named VoxPocket runner service when idle, restore timestamped file backups, reload the same LaunchAgent label, and re-check online state. Do not modify machine-global network settings.
- **Tracked repair**: Revert the exact repair commit by a protected-branch PR; never rewrite protected history.
- **Observer bootstrap**: Disable the existing trigger first, restore the observer's prior explicit configuration, and retain failed/probe run IDs. Never delete the autopilot or change shared agents.
- **PR shipping**: If the head changes, invalidate stale review/check evidence and repeat exact-head review. Do not force-push or synthesize status.
- **Benchmark harness**: Revert only through a protected-branch PR. Private reports stay in the protected benchmark directory; do not delete or relocate the owner fixture. A failed provider run becomes `unavailable`, not a fallback result.
- **App install**: Preserve the prior app backup and all archives; if replacement or acceptance fails, gracefully stop the new app, restore the backup, and retain the evidence bundle.
- **Telemetry**: Stopping the local stack or clearing acceptance-window records must not delete app sandbox data. Pending telemetry remains inside the app sandbox and is never copied into planning evidence.

## Root-Coordinator Handoff

The worker that completes US3/US4 posts a handoff conforming to [contracts/recovery-evidence.md](./contracts/recovery-evidence.md) with runtime ownership, observer state, `pr_state=MERGED`, feature and benchmark merge SHAs, `remote_main_sha`, all required-check URLs, repair rollback, and any operational caveats. It explicitly addresses the root coordinator and performs no primary-checkout, protected-fixture, or `/Applications` mutation itself.

The current-Mac Fullstack/local-validation operator executes US4's private benchmark only under root-coordinator coordination. The root coordinator owns US5 and US6 and returns the completed benchmark/install/acceptance fields to Team Lead. A missing runtime proof, successful observer probe, merged revision, benchmark privacy result, pre-install human-state confirmation, backup path, exact SHA, or real-app privacy result blocks completion.

## Complexity Tracking

No constitution violation or new architecture layer is accepted. RepoInfra remains documentation/task ownership. The benchmark adds only a narrow testability seam inside existing VoxInfrastructure/TranscriptionKit and a test-harness adapter; it does not add a product dependency, UI, backend, or default-model change.
