# Feature Specification: MY-1540 RepoInfra Recovery and Logging Delivery

**Feature Branch**: `agent/planner-lead/61b8ffb64655`

**Created**: 2026-09-10

**Status**: Ready-for-review candidate

**Input**: Recover the mobile-Mac review runner without weakening protection, ship existing PR #35, then perform the owner-authorized post-merge installation and prove real VoxPocket logs reach the local telemetry stack without private content.

## User Scenarios & Testing

### User Story 1 - Produce a falsifiable runner diagnosis (Priority: P1)

As the delivery owner, I need the failed review gate diagnosed from the same service context that runs the required check so that a successful retry is attributable to a known cause rather than luck.

**Why this priority**: Every later action depends on knowing whether sleep/offline state, service environment inheritance, provider connectivity/authentication, or an unnecessary startup dependency caused the cancellation.

**Independent Test**: Starting from PR #35 at the recorded candidate revision, an operator can present a redacted evidence bundle that compares all four hypotheses, names one supported root cause (or a bounded unresolved dependency), and identifies a falsifier and repair target.

**Acceptance Scenarios**:

1. **Given** the runner process is online but the review request failed, **when** probes run in the runner service context, **then** the evidence distinguishes runner availability from upstream reachability and authentication.
2. **Given** interactive-shell connectivity differs from the service context, **when** environment inheritance is compared, **then** only non-secret settings and outcomes are recorded.
3. **Given** evidence does not justify an endpoint, credential, provider, or model change, **when** diagnosis finishes, **then** the work stops and requests an owner decision rather than inventing configuration.

---

### User Story 2 - Bootstrap the existing task-specific supervisor (Priority: P2)

As the delivery owner, I need the existing MY-1540 autopilot to run successfully on its dedicated NAS runtime so it can observe, dispatch, perform bounded reruns, and report without becoming an implementation agent.

**Why this priority**: The existing supervisor is not operational: its first two runs failed because its empty model selection resolved to an unsupported default. A working observer is required before the longer delivery sequence begins.

**Depends on**: User Story 1's runtime inventory and ownership evidence; it does not depend on changing the current-Mac runner.

**Independent Test**: The existing disabled schedule remains disabled while the NAS runtime's supported model catalog is inspected, the dedicated observer receives one compatible explicit configuration, one authorized probe completes successfully, and only then the existing `*/10` trigger is enabled.

**Acceptance Scenarios**:

1. **Given** the Dev Team roles are bound to the current-Mac daemon and the observer is a distinct NAS-bound agent, **when** runtime ownership is recorded, **then** no role is moved to the legacy offline daemon and no shared agent is changed.
2. **Given** the existing observer's two failed runs name an unsupported default model, **when** its NAS runtime catalog is inspected, **then** one compatible model/effort/service-tier combination is selected for that observer only.
3. **Given** the trigger is disabled, **when** one explicit probe succeeds and its behavior stays within observe/dispatch/bounded-rerun/report scope, **then** the existing schedule is enabled without creating another autopilot or scheduler.
4. **Given** delivery reaches final acceptance, **when** the completion record is verified, **then** the task-specific schedule is disabled.

---

### User Story 3 - Recover the required gate and ship PR #35 (Priority: P3)

As the delivery owner, I need a reversible, independently reviewed RepoInfra repair that restores the real required review and lets the existing logging PR merge through normal repository protections.

**Why this priority**: The logging implementation is already complete in PR #35; delivery is blocked only by the required review control plane.

**Depends on**: User Stories 1 and 2.

**Independent Test**: A safe disconnect/recovery exercise fails explicitly and recovers without changing global network settings; the required `codex-review-target` then passes against the current exact PR head, every required check is green, and GitHub reports PR #35 merged by the enabled repository mechanism.

**Acceptance Scenarios**:

1. **Given** a supported root cause and a captured backup, **when** the smallest repair is applied, **then** actual Codex review, exact-head validation, read-only execution, fail-closed behavior, and required-check names remain intact.
2. **Given** an isolated connectivity failure, **when** the review path is exercised, **then** it reports unavailability promptly instead of relying only on a silent 25-minute reconnect loop.
3. **Given** recovery evidence and independent approval of any changed artifact, **when** the required check is rerun, **then** the check is a real review of the current PR head and not a synthetic status.
4. **Given** all required checks pass, **when** auto-merge executes, **then** PR #35 is confirmed merged without force-push, admin merge, gate removal, or direct push to `main`.

---

### User Story 4 - Benchmark production transcription adapters safely (Priority: P4)

As the delivery owner, I need a separate TranscriptionKit test harness to compare the production recognition adapters on the approved mixed-language fixture without exposing the fixture or silently changing product behavior.

**Why this priority**: The benchmark is an owner-approved evidence task, not part of the logging implementation, and must ship independently before local validation and installation.

**Depends on**: User Story 3 for normal delivery controls; it ships through its own reviewed PR.

**Independent Test**: On the current Mac, the harness reads only the protected sandbox manifest, uses identical decoded audio for serial cold/warm and real-time-paced runs, emits only sanitized numeric summaries, and produces a private full-text report plus an evidence-bounded recommendation.

**Acceptance Scenarios**:

1. **Given** the owner fixture in the app sandbox, **when** the harness runs, **then** audio/reference/output text and private filenames stay in that protected directory and do not enter Git, stdout, Loki, or issue comments.
2. **Given** Apple Speech, the configured Azure deployment, WhisperKit base, and WhisperKit large-v3-turbo, **when** each supported group is tested, **then** it receives one cold and five warm serial runs on identical decoded audio, with downloads/conversion/model loading timed separately.
3. **Given** batch and real-time-paced modes, **when** measurements are reported, **then** they distinguish model load, request duration, first partial, stable-final-after-input, total latency, and real-time factor; cloud time includes network and five runs are not labeled p95.
4. **Given** the exact owner reference, **when** accuracy is scored, **then** English is case-folded, punctuation is separate, CER and mixed Chinese-character/English-word token error rate are reported, and preservation of the English word `test` is inspected.
5. **Given** hybrid pipelines, **when** Apple+Azure and Apple+local Whisper are measured, **then** final ASR, merger, and refinement stages are separated; pure-ASR runs disable refinement and never receive the reference text.
6. **Given** a missing provider, credential, or unobservable Apple mode, **when** the run is classified, **then** it is reported unavailable/unknown without fallback mislabeling or a new endpoint/credential.
7. **Given** the numeric results, **when** a recommendation is made, **then** it is explicitly case-specific and does not change the product default.

---

### User Story 5 - Install a fresh build from merged main (Priority: P5)

As the authorized local user, I need the old app replaced by a newly built macOS Debug app from the latest remote `main` while preserving my current app, data, preferences, and private model configuration.

**Why this priority**: Telemetry acceptance must exercise the shipped application rather than the pre-merge archive or a test harness.

**Depends on**: User Stories 3 and 4, including their independently reviewed merged revisions.

**Independent Test**: The root coordinator records the merged source revision and dependency revision, produces a new archive, verifies the old app is idle and has no unsaved text, backs it up, installs the new app, and confirms exactly one instance is open; rollback restores the recorded backup.

**Acceptance Scenarios**:

1. **Given** PR #35 is merged, **when** the root coordinator syncs from remote `main`, **then** the build record names the exact source revision, dependency revision, and clean/dirty state.
2. **Given** the old app is not recording and has no unsaved text, **when** replacement begins, **then** the current `/Applications/VoxPocket.app` is backed up before a graceful quit and replacement.
3. **Given** installation succeeds, **when** VoxPocket is reopened, **then** one instance runs and the existing sandbox data, preferences, and private model configuration remain in place.
4. **Given** build, validation, replacement, or launch fails, **when** rollback is invoked, **then** the backup app is restored and the failure is reported without deleting retained archives.

---

### User Story 6 - Prove real-app telemetry and privacy (Priority: P6)

As the delivery owner, I need proof that the installed VoxPocket app emits useful local logs and does not upload voice, text, prompts, credentials, or arbitrary error bodies.

**Why this priority**: A smoke harness proves the library but not the installed application's wiring or privacy behavior.

**Depends on**: User Story 5.

**Independent Test**: Launching the installed app and performing one harmless window action yields time-bounded records in the VoxPocket log stream and a ready dashboard, while an inspection of emitted fields finds no forbidden content. No voice recording is needed.

**Acceptance Scenarios**:

1. **Given** the local telemetry stack is healthy and the installed app is closed, **when** the app starts and one harmless window operation is performed, **then** new records appear in the dedicated VoxPocket application-log stream.
2. **Given** those records, **when** their message and context fields are inspected, **then** they contain only reviewed fixed messages, approved metadata, and redaction placeholders.
3. **Given** the acceptance run finishes, **when** the handoff is written, **then** it includes app path, backup path, source and merge revisions, exact query, time window, count, dashboard readiness, and privacy result.

### Edge Cases

- The runner is online but the provider endpoint is unreachable only from the service context.
- The laptop sleeps or changes networks while no job is running, then wakes with stale service connectivity.
- Provider authentication is expired; this must not be disguised as a proxy failure.
- A proposed proxy address is not a forward proxy, or the owner has not approved a new endpoint/credential/model.
- A repair requires a repository change rather than a host-only configuration change.
- PR #35's head changes after diagnosis; all approvals and checks must bind to the new exact head.
- Auto-merge is enabled but the base branch advances, requiring the branch to become current under repository policy.
- The old app is recording, has unsaved text, is not installed, or cannot be quit gracefully.
- The new archive fails validation or the installed app fails to open; rollback must remain available.
- Loki or Grafana is unavailable, records are delayed, or only a library smoke record appears.
- A log contains unexpected dynamic text or secret-like material; acceptance fails even if records arrive.
- A runtime display name suggests a different computer even though its daemon identifier proves current-Mac ownership.
- The observer remains bound to its intended NAS runtime but its empty model field resolves to an unsupported default.
- A benchmark provider is unavailable, Apple on-device/server routing is unobservable, or Azure deployment identity cannot be proved.
- Download, conversion, or model-load time contaminates recognition timing, or a fallback is mislabeled as the requested provider.
- Full recognized text or a private fixture filename escapes the protected benchmark directory.

## Requirements

### Functional Requirements

- **FR-001**: The diagnosis MUST test runner availability, service-context network/proxy inheritance, provider connectivity/authentication, and startup dependencies as separate hypotheses.
- **FR-002**: The diagnosis MUST record a falsifiable root cause, supporting and contradicting evidence, a falsifier, and an exact repair target; if evidence remains inconclusive, execution MUST stop at a bounded escalation.
- **FR-003**: Diagnostic and review evidence MUST be redacted and MUST NOT disclose credentials, tokens, configuration contents, or user content.
- **FR-004**: Any repair MUST be limited to the VoxPocket review runner/control plane, have a backup and tested rollback, and avoid unrelated runners and machine-global network settings.
- **FR-005**: Any repair MUST preserve actual Codex review, exact-head validation, read-only sandboxing, fail-closed behavior, and existing required-check names.
- **FR-006**: Recovery verification MUST include a safely isolated failure and recovery path that does not disrupt the owner's global connection.
- **FR-007**: Endpoint, credential, provider, model, or authentication changes MUST require an explicit owner decision when existing evidence does not already authorize the value.
- **FR-008**: PR #35 MUST remain the logging-delivery vehicle; the implementation MUST NOT be recreated or replaced by a new logging feature.
- **FR-009**: Any repair artifact MUST receive independent review at its exact revision before it is used to satisfy the required gate.
- **FR-010**: The required review MUST pass against the current exact PR #35 head, followed by every repository-required check passing and GitHub confirming the PR is merged through the approved mechanism.
- **FR-011**: Delivery MUST NOT use synthetic statuses, remove or rename a gate, force-push, admin-merge, directly push protected `main`, or bypass hooks.
- **FR-012**: After merge, only the root coordinator may synchronize the user's primary checkout and perform the authorized build/install sequence.
- **FR-013**: The post-merge build MUST be a new macOS Debug archive from latest remote `main` plus the published LokiKit dependency and MUST record source revisions and clean/dirty state.
- **FR-014**: Before replacement, the coordinator MUST verify the old app is not recording and has no unsaved user text, back up the installed app, and quit it gracefully.
- **FR-015**: Installation MUST preserve existing archives, app sandbox data, preferences, and private model configuration, then reopen exactly one app instance.
- **FR-016**: Installation MUST have a tested rollback procedure that restores the recorded backup if archive validation, replacement, launch, or acceptance fails.
- **FR-017**: Acceptance MUST use the installed VoxPocket application, one startup event, and a harmless window operation; a LokiKit smoke test alone is insufficient and no voice may be recorded without separate permission.
- **FR-018**: Acceptance MUST query the dedicated application-log stream over an exact time window, record the query and count, and verify the dashboard is ready.
- **FR-019**: Acceptance MUST verify that transcript, prompt, refined text, credentials, and arbitrary error bodies are absent from uploaded records.
- **FR-020**: Final evidence MUST include the app path, backup path, source and merge revisions, query, time window, record count, dashboard readiness, privacy result, and rollback status.
- **FR-021**: Runtime evidence MUST prove Team Lead, Planner Lead, and AI Reviewer use Codex runtime `ab653716-b90e-40f1-b6ff-5095f818a1f8`, Fullstack Engineer and PR Manager use Copilot runtime `05eda9df-e582-43e1-b8e0-3c16f847522d`, and both belong to current-Mac daemon `019fd055-0738-723e-a556-762fc863b720`; no Dev Team role may use legacy daemon `019e2a6c-e1d4-737a-afca-e945ec0c8137`.
- **FR-022**: The existing autopilot `d67e7307-d0ef-40c4-a597-fd48d73cda48`, observer agent `efc285c0-5c91-4055-80ba-e64b9d6419f9`, NAS runtime `a06e54f0-65cf-46ea-96de-97da512438cf`, and disabled trigger `52310b59-fd61-4cf7-ae14-523ae55d2a26` MUST be reused. A compatible runtime-catalog configuration and one successful probe MUST precede enabling that trigger; no new scheduler/autopilot or shared-agent change is allowed.
- **FR-023**: The external PR #35 adoption record MUST associate MY-1540, repository, exact head/base, accepted scope, existing evidence, and Team Lead-provisioned isolated delivery workspace before PR Manager supervision.
- **FR-024**: Benchmark implementation MUST be a separate VoxInfrastructure/TranscriptionKit test-harness child and separate reviewed PR; it MUST NOT add a UI, backend, default-model change, or production product flow unrelated to test injection.
- **FR-025**: The benchmark MUST read only `/Users/tianpli/Library/Containers/com.leepepe.voxpocket/Data/Library/Application Support/VoxPocket/benchmarks/owner-20260910/manifest.json` and sibling fixture files on the current Mac. The NAS observer MUST NOT read or copy them.
- **FR-026**: The benchmark MUST compare Apple Speech, the verified existing Azure speech deployment, WhisperKit base, WhisperKit large-v3-turbo, Apple+Azure, and Apple+local Whisper; unavailable or unobservable modes MUST be labeled honestly without fallback substitution.
- **FR-027**: Each supported benchmark group MUST use identical decoded audio, serial execution, one cold run and five warm runs, with downloads, conversion, and model loading measured separately from recognition.
- **FR-028**: Benchmark results MUST distinguish batch from real-time-paced 16.213-second input and report model loading, request duration, first partial, stable final after input end, total latency, and real-time factor. Cloud duration MUST be labeled as network-inclusive; five samples MUST be summarized as individual values, median, and range, never p95.
- **FR-029**: Accuracy scoring MUST use the exact owner reference without providing it to a recognizer or refinement model, case-fold English, score punctuation separately, report CER and mixed Chinese-character/English-word token error rate, and explicitly inspect the English word `test`.
- **FR-030**: Pure-ASR comparisons MUST disable refinement. Hybrid comparisons MUST report final-ASR, merger, and refinement stages separately and MUST NOT describe hybrid routes as independent models.
- **FR-031**: Full benchmark audio, reference, recognized text, private filenames, secrets, and arbitrary service error bodies MUST remain in the owner-only benchmark directory (directory mode 0700; report files 0600). Public evidence is limited to sanitized numeric summaries and approved model/source labels, with legacy plaintext provider logging suppressed in the harness.
- **FR-032**: Any benchmark recommendation MUST be scoped to the single approved mixed-language fixture and MUST NOT silently change the product default.

### Key Entities

- **Diagnosis Evidence**: Redacted observations, hypothesis matrix, root cause, falsifier, repair target, and exact PR/runner context.
- **Repair Candidate**: The smallest host or repository change, its exact revision or digest, backup, rollback, and independent-review verdict.
- **Shipping Record**: Exact PR head, required-check results, merge mechanism, merge revision, and remote-main revision.
- **Install Record**: Source/dependency revisions, workspace state, archive path, installed path, backup path, process state, and rollback result.
- **Telemetry Acceptance Record**: User action, query, time window, record count, dashboard state, and privacy inspection result.
- **Runtime Ownership Record**: Agent-to-runtime-to-daemon mapping, online state, observation time, and explicit legacy-daemon exclusion.
- **Supervisor Bootstrap Record**: Existing autopilot/agent/runtime/trigger identifiers, supported model selection evidence, probe result, schedule state, and completion-disable state.
- **External PR Adoption Record**: MY-1540, repository, delivery workspace metadata, exact head/base, scope, evidence, and PR Manager handoff.
- **Benchmark Run**: Provider/pipeline identity, verified underlying model/deployment, pacing mode, cold/warm ordinal, stage timings, availability, and sanitized numeric scores.
- **Benchmark Report**: Private full-text artifact path, public numeric summary, single-fixture limitation, and non-binding recommendation.

## Success Criteria

### Measurable Outcomes

- **SC-001**: One evidence bundle evaluates all four required failure classes and names either one falsifiable root cause or one precise owner-dependent blocker.
- **SC-002**: A simulated isolated outage produces an explicit unavailable result within 120 seconds, and the same path succeeds after recovery without a machine-global network change.
- **SC-003**: The required review and every other required check pass on one recorded exact PR head, and PR #35 reaches the merged state through repository automation.
- **SC-004**: One new post-merge archive is created and verified; one backup of the prior installed app is retained; exactly one new app instance is running after installation.
- **SC-005**: At least one startup record and one harmless window-operation record from the installed app appear in the dedicated stream within a recorded five-minute query window.
- **SC-006**: Inspection of all records returned for the acceptance window finds zero transcript, prompt, refined-text, credential, or arbitrary-error-body values.
- **SC-007**: The final handoff contains every evidence field in FR-020 and is sufficient to execute the documented rollback without rediscovery.
- **SC-008**: Runtime ownership evidence maps all five Dev Team roles to the two online current-Mac runtimes and maps zero Dev Team roles to the legacy daemon.
- **SC-009**: One observer probe completes successfully after a catalog-valid configuration is applied to the existing observer, after which the existing 10-minute trigger is enabled; no additional autopilot or schedule exists.
- **SC-010**: Every supported benchmark group has exactly one cold and five warm serial runs in each applicable pacing mode, with complete timing and accuracy fields; public output contains zero private text, filenames, secrets, or arbitrary error bodies.
- **SC-011**: The benchmark and PR #35 each ship through independently reviewed exact revisions before root-coordinator validation/install begins.

## Assumptions

- Owner authorization in MY-1540 covers replacing `/Applications/VoxPocket.app` after merge, but does not authorize global proxy changes, new credentials/endpoints/models, voice recording, or TestFlight distribution.
- PR #35 and published LokiKit remain the existing logging implementation sources; the only additional product-layer work is the separately approved VoxInfrastructure/TranscriptionKit benchmark testability seam and harness.
- The local Loki/Grafana stack remains loopback-only and may be started or checked as part of acceptance.
- The user's primary checkout and final installed app remain under root-coordinator control; delivery workers use the isolated task checkout.
- A host-only repair can be reviewed by exact backup/diff/digest evidence even when it has no Git commit; any repository repair must use a protected-branch PR.
- The observer is intentionally NAS-bound and is not a Dev Team role; current-Mac role reconciliation does not authorize moving it.
- The approved fixture is one 16.213-second mixed-language sample and supports a case-specific comparison only.

## Non-Goals

- Reimplementing or extending logging behavior already present in PR #35.
- Modifying VoxDomain, VoxApplication, VoxPresentation, VoxUITesting, LokiKit, or any VoxInfrastructure path outside the explicitly scoped TranscriptionKit benchmark seam/test harness.
- Changing global network settings or unrelated runner installations.
- Weakening, renaming, synthesizing, or bypassing required checks.
- Recording voice, uploading historical content, distributing through TestFlight, or changing model/provider configuration without a new owner decision.
- Creating a new autopilot/scheduler, moving the observer off its dedicated NAS runtime, or changing shared agents/projects.
- Copying benchmark fixture data to NAS, Git, issue comments, Loki, or any location outside the protected current-Mac benchmark directory.
- Adding a settings UI, ASR backend, default recognition-model change, or universal accuracy claim.
