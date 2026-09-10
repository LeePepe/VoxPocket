# Research: MY-1540 RepoInfra Recovery and Logging Delivery

## Decision 1: Treat the failure as an observable RepoInfra timeout, not a proven network cause

**Decision**: Begin with a bounded read-only diagnosis in the actual runner service context. Test runner lifecycle, service environment/proxy inheritance, upstream TCP/TLS reachability, authenticated provider behavior, and startup dependencies separately.

**Rationale**: Run `34474957893` attempt 2 reached the Codex invocation and was killed by the 25-minute job timeout after emitting only the start line. The runner stayed online. Interactive `chatgpt.com:443` timed out, but that does not prove the runner's service context, authentication, or MCP startup path failed for the same reason.

**Alternatives considered**:

- Attribute the incident only to laptop movement/sleep: rejected because this is an owner hypothesis without discriminating evidence.
- Configure local ports 3000/8080 as HTTPS proxies: rejected because CONNECT returned 400 and they are not established forward proxies.
- Rerun until green: rejected because it does not produce a falsifiable cause or recovery contract.

## Decision 2: Keep one RepoInfra seam and do not invent a product layer

**Decision**: Scope diagnosis and repair to the top-level operational RepoInfra/control-plane paths named in the issue and repository. No `RepoInfra/` package or new dependency layer is created.

**Rationale**: The repository declares five Swift package layers; the app shell is not a layer, and no RepoInfra directory or tech-context exists. The failure belongs to runner/review infrastructure, not the logging implementation.

**Alternatives considered**:

- Classify the work as VoxInfrastructure: rejected because that package owns app runtime capabilities, not CI or runner operation.
- Add a new repository layer: rejected because the repair does not justify architecture expansion.

## Decision 3: Use diagnose-then-select repair with a strict path allowlist

**Decision**: The diagnostic task emits one `repair_target`. The repair task may touch only the selected target within:

- `/Users/tianpli/Library/LaunchAgents/actions.runner.LeePepe-VoxPocket.macmini-local.plist`
- `/Users/tianpli/.codex-review/`
- `.github/workflows/codex-review-target.yml`
- `scripts/ci/codex-review.sh`
- `scripts/ci/tests/test_codex_review_preflight.sh`
- `scripts/ci/tests/test_runner.sh`

Every changed host file receives a timestamped checksum-recorded backup. Any tracked repair uses a normal PR. An endpoint/credential/provider/model/auth change is an owner decision, not a default repair.

**Rationale**: The exact failing implementation and service surfaces are known, but the root-cause path is not. A bounded spike avoids guessing while giving the next task deterministic input.

**Alternatives considered**:

- Preselect a proxy change: rejected as unsupported and too broad.
- Let the implementer search the entire machine: rejected because it violates scope and risks secrets/unrelated runtimes.
- Combine diagnosis and repair: rejected because the repair would be impossible to review against a falsifiable premise.

## Decision 4: Preserve a fail-closed review while making unavailability explicit

**Decision**: Keep actual Codex execution, the read-only sandbox, exact-head inputs, and `codex-review-target` required context. If a tracked repair is needed, it adds bounded preflight/progress/failure reporting and focused tests without turning infrastructure errors into PASS.

**Rationale**: The current script captures stderr only after the synchronous Codex process returns; workflow cancellation destroys the temporary diagnostics. Faster and durable failure classification is needed, but safety semantics cannot weaken.

**Alternatives considered**:

- Increase the 25-minute timeout only: rejected because it prolongs silent failure and hides the cause.
- Mark infrastructure failure neutral/success: rejected because it would make the gate fail open.
- Replace Codex review with Kimi advisory status: rejected because Kimi is explicitly not the required gate.

## Decision 5: A tracked repair must land before PR #35 is refreshed

**Decision**: If repository review logic changes, merge that independently reviewed RepoInfra PR to `main` first. Then bring PR #35 up to date with the repaired base, capture its new head, and run every required check on that exact head.

**Rationale**: `pull_request_target` evaluates workflow and script content from the default branch. A repair present only on PR #35 cannot repair its own gate. The strict ruleset also requires the feature branch to be current.

**Alternatives considered**:

- Commit the repair only to PR #35: rejected because the trusted workflow still comes from the old base.
- Bypass or rename the required check: rejected by repository and owner policy.

## Decision 6: Reuse PR #35 and published LokiKit exactly

**Decision**: PR #35 remains the logging delivery vehicle. Its current pre-refresh head is `6066a66ceaa52ddedc74136352913f70daa9e160`; LokiKit is already published at `eff9c1712cd648ed0717e41183ad8bd7bf39cbea`. Any refreshed PR head is recorded before review.

**Rationale**: The five SPM checks, App target, Lint/policy, logging harness, startup tests, and archive evidence already passed for the candidate. The only required failure is the cancelled Codex review.

**Alternatives considered**:

- Recreate logging on a new branch or PR: rejected as duplicate work and a loss of reviewed evidence.
- Modify LokiKit: rejected because it is external, already published, and out of scope.

## Decision 7: Root coordinator exclusively owns the post-merge primary-checkout and install operations

**Decision**: After merge proof, the delivery worker sends a structured handoff. The root coordinator synchronizes `/Users/tianpli/Development/VoxPocket/`, preserves its unrelated untracked paths, builds the new archive with the published LokiKit sibling, backs up `/Applications/VoxPocket.app`, installs, opens one instance, and performs acceptance.

**Rationale**: The task checkout lacks the required LokiKit sibling; the primary checkout has it but also contains unrelated untracked directories. The issue explicitly reserves this surface for the root coordinator.

**Alternatives considered**:

- Build from the isolated task checkout: rejected because its relative LokiKit dependency is missing.
- Use the old archive: rejected because it predates the merge.
- Use legacy release scripts as an installer: rejected because they copy artifacts into `releases/` and do not replace `/Applications/VoxPocket.app`.

## Decision 8: Accept only real installed-app logs using a safe marker

**Decision**: Record a launch timestamp, wait beyond the two-second sink interval, perform a harmless window action, and query the exact safe startup marker within `{app="VoxPocket",stream="log"}`. Also prove dashboard readiness and inspect the full acceptance window for forbidden content.

**Rationale**: The current installed app predates PR #35 and the log stream is empty, providing a clean before/after discriminator. `Local log collection started` is an exact allowlisted fixed message. Library smoke tests do not prove installed-app wiring.

**Alternatives considered**:

- Use only `scripts/tests/test_app_logging.py`: rejected because it is a harness, not the installed app.
- Record voice to generate activity: rejected because the owner did not authorize voice capture for testing.
- Query or display transcript fields: rejected by the privacy constitution.

## Resolved Unknowns

- **Current PR state**: Open and mergeable but blocked; auto-squash merge enabled; only required Codex review is cancelled.
- **Required checks**: Five SPM contexts, App target, Lint & policy, and `codex-review-target`.
- **Review failure boundary**: Synchronous Codex execution exceeded the workflow timeout; underlying provider/runtime/network cause remains to be diagnosed.
- **Install authority**: Explicitly granted for a post-merge local replacement, excluding TestFlight.
- **Telemetry baseline**: Loki and Grafana are healthy; current installed app has no dedicated application-log stream.
- **Unresolved owner-only inputs**: Any new endpoint, credential, provider, model, or authentication selection. Encountering one blocks repair and produces an escalation.
- **Current-Mac Dev Team runtimes**: Codex `ab653716-b90e-40f1-b6ff-5095f818a1f8` and Copilot `05eda9df-e582-43e1-b8e0-3c16f847522d`, both on daemon `019fd055-0738-723e-a556-762fc863b720` and online at the latest read.
- **Observer failure**: Existing autopilot is active but its `*/10` trigger is disabled; both run records failed with the same unsupported `gpt-5.4` default-model classification. The observer agent model is blank and resolves through the NAS runtime default.
- **Benchmark authority**: The owner approved sending only the supplied fixture to the existing configured Azure speech service and approved current-Mac local benchmark execution; NAS access, new services/credentials, and default changes are not authorized.

## Decision 9: Keep Dev Team execution on the current Mac and the observer on its existing NAS runtime

**Decision**: Record runtime-to-daemon identity before dispatch. Team Lead, Planner Lead, and AI Reviewer remain on Codex runtime `ab653716-b90e-40f1-b6ff-5095f818a1f8`; Fullstack Engineer and PR Manager remain on Copilot runtime `05eda9df-e582-43e1-b8e0-3c16f847522d`; both belong to current-Mac daemon `019fd055-0738-723e-a556-762fc863b720`. The task-specific observer remains on NAS runtime `a06e54f0-65cf-46ea-96de-97da512438cf`. No Dev Team role may bind to legacy daemon `019e2a6c-e1d4-737a-afca-e945ec0c8137`.

**Rationale**: Runtime display names are not physical-machine authority. The owner and Team Lead reconciled exact IDs, while the observer is deliberately external to the Dev Team execution roles.

**Alternatives considered**:

- Move every agent to the NAS: rejected because implementation and PR supervision require current-Mac access.
- Move the observer to the current Mac: rejected because the owner approved the existing NAS-bound automation.
- Use the legacy daemon: rejected because it is offline and explicitly excluded.

## Decision 10: Repair the existing autopilot by catalog-first configuration

**Decision**: Reuse autopilot `d67e7307-d0ef-40c4-a597-fd48d73cda48`, observer `efc285c0-5c91-4055-80ba-e64b9d6419f9`, and disabled `*/10` trigger `52310b59-fd61-4cf7-ae14-523ae55d2a26`. Inspect the NAS runtime's supported model/effort/service-tier catalog, apply one compatible explicit configuration to the observer only, run one authorized probe, and enable the existing trigger only after success.

**Rationale**: Both existing runs failed deterministically because the blank observer model resolved to unsupported `gpt-5.4` for a ChatGPT-account Codex runtime. Trial-and-error reruns would waste work and the trigger is correctly disabled.

**Alternatives considered**:

- Create a replacement scheduler or autopilot: rejected by explicit owner instruction.
- Change shared agents/runtime defaults: rejected because the scope is one dedicated observer.
- Enable first and see whether a later run works: rejected because it would create recurring known failures.

## Decision 11: Build a separate TranscriptionKit benchmark harness and keep all text private

**Decision**: Add a separate VoxInfrastructure/TranscriptionKit test-harness slice and reviewed PR. It reuses production adapters through a narrow file/buffer injection seam, runs only on the current Mac against the protected sandbox fixture, and writes full text only inside that directory. Public output is numeric and uses approved provider/model labels.

**Rationale**: Production adapters are the behavior under evaluation, speaker replay would add uncontrolled acoustic variance, and current production logging includes paths that can render provider text. A harness-owned silent/sanitizing logger and private report sink keep the benchmark compliant without changing default product behavior.

**Alternatives considered**:

- Re-record audio through speakers: rejected because the input would no longer be identical and would involve microphone capture.
- Write fixture/output text to XCTest or CLI stdout: rejected by owner privacy constraints.
- Feed reference text to recognition/refinement for scoring convenience: rejected because it contaminates the measurement.
- Present five warm samples as p95: rejected as statistically unsupported.
