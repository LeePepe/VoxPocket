# Data Model: MY-1540 Recovery Evidence

This feature introduces no application persistence schema. The model below defines the operational records passed between tasks and retained in Multica comments or PR evidence. Secret values and user content are never fields.

## Entities

### CandidateIdentity

| Field | Type | Validation |
|---|---|---|
| `repository` | string | Exactly `LeePepe/VoxPocket` |
| `pr_number` | integer | Exactly `35` for the logging delivery |
| `base_sha` | 40-char SHA | Must match the observed base at probe/review time |
| `head_sha` | 40-char SHA | Must match GitHub `headRefOid`; recapture after any refresh |
| `observed_at` | UTC timestamp | Required |

### DiagnosisEvidence

| Field | Type | Validation |
|---|---|---|
| `candidate` | CandidateIdentity | Required |
| `runner_label` | string | Exact registered VoxPocket label; no unrelated runner |
| `service_state` | enum | `online`, `offline`, `sleep_recovery_pending`, `unknown` |
| `hypotheses` | list | Contains lifecycle, proxy inheritance, provider connectivity/auth, startup dependency |
| `observations` | list | Redacted commands/outcomes only |
| `root_cause` | string | Falsifiable statement; no secret values |
| `falsifier` | string | A concrete observation that would disprove the root cause |
| `repair_target` | path list | Subset of the plan's allowlist |
| `owner_decision_required` | boolean | True for new endpoint/credential/provider/model/auth choice |

### RepairCandidate

| Field | Type | Validation |
|---|---|---|
| `diagnosis_ref` | reference | Points to exact DiagnosisEvidence |
| `kind` | enum | `host_config`, `repository`, `none_owner_blocked` |
| `changed_paths` | path list | Exact allowlisted paths only |
| `before_digest` | string | Required for every changed host file |
| `after_digest_or_commit` | string | Digest for host repair or Git commit SHA for tracked repair |
| `backup_paths` | path list | Required for host repair; timestamped and checksum verified |
| `rollback_steps` | ordered list | Restores exact prior state |
| `review_verdict` | enum | `pending`, `pass`, `changes_requested` |
| `reviewed_revision` | string | Must equal `after_digest_or_commit` on PASS |
| `actual_codex_execution` | tuple | Completed `codex exec` evidence reference, not a synthetic check |
| `sandbox_invariant` | tuple | Observed `read-only` mode and `approval_policy=never` evidence |
| `exact_head_invariant` | tuple | Expected and reviewed PR head SHAs are equal |
| `required_check_invariant` | tuple | Observed check name is exactly `codex-review-target` and preserved |

### RecoveryProof

| Field | Type | Validation |
|---|---|---|
| `failure_injection` | string | Isolated to test process/service; never global network |
| `failure_latency_seconds` | number | Must be `<= 120` |
| `failure_result` | string | Explicit unavailable/fail-closed result |
| `recovery_action` | string | Exact, reversible action |
| `recovery_result` | string | Same review interface completes after restoration |
| `global_network_changed` | boolean | Must be false |

### ShippingRecord

| Field | Type | Validation |
|---|---|---|
| `repair_pr` | URL or null | Required only for tracked repair |
| `repair_merge_sha` | SHA or null | Required only for tracked repair |
| `feature_pr` | URL | Exactly PR #35 |
| `feature_head_sha` | SHA | Current exact head after any base refresh |
| `required_checks` | map | All eight required contexts have conclusion `success` for `feature_head_sha` |
| `merge_mechanism` | enum | Repository-approved auto-merge/squash mechanism |
| `feature_merge_sha` | SHA | GitHub-reported merge commit |
| `remote_main_sha` | SHA | Must contain/equal the merged state at handoff |

### InstallRecord

| Field | Type | Validation |
|---|---|---|
| `source_sha` | SHA | Latest remote `main`; includes feature merge |
| `lokikit_sha` | SHA | Published dependency revision |
| `workspace_state` | string | Clean/dirty plus preserved unrelated paths; no cleanup |
| `archive_path` | absolute path | New timestamped `.xcarchive` |
| `archive_app_path` | absolute path | Exists under `Products/Applications/VoxPocket.app` |
| `installed_app_path` | absolute path | `/Applications/VoxPocket.app` |
| `backup_app_path` | absolute path | Timestamped, exists until acceptance/handoff |
| `backup_identity` | tuple | Backup path, bundle identifier, version, build, and code-directory hash match the pre-install app |
| `preflight_idle` | boolean | True only after not-recording/no-unsaved-text confirmation |
| `running_instances` | integer | Exactly `1` after launch |
| `private_config_preserved` | boolean | Required; content not inspected or copied into evidence |
| `rollback_status` | enum | `available`, `executed`, `not_available` (`not_available` blocks) |
| `rollback_rehearsal` | tuple | Method, timestamp, result, and restored identity; result must be `pass` while backup remains retained |

### TelemetryAcceptance

| Field | Type | Validation |
|---|---|---|
| `action` | string | Startup plus harmless window operation; no voice |
| `query` | string | Includes `{app="VoxPocket",stream="log"}` and safe marker |
| `start_utc` | UTC timestamp | At or immediately before app launch |
| `end_utc` | UTC timestamp | No more than five minutes after start for primary proof |
| `record_count` | integer | At least 2 total records, including startup and window-operation evidence |
| `startup_marker_count` | integer | At least 1 |
| `startup_marker_timestamp` | UTC timestamp | Inside the recorded query window |
| `window_marker` | enum | One allowlisted show/hide/close message tied to the performed action |
| `window_marker_count` | integer | At least 1, counted independently from startup |
| `window_marker_timestamp` | UTC timestamp | Inside the query window and after the recorded action |
| `dashboard_url` | URL | Local `/d/voxpocket-logs` dashboard |
| `dashboard_ready` | boolean | Must be true |
| `forbidden_content_count` | integer | Must be `0` |
| `privacy_notes` | string | Names inspected fields/categories, never the forbidden values |

### RuntimeOwnership

| Field | Type | Validation |
|---|---|---|
| `current_mac_daemon` | UUID | Exactly `019fd055-0738-723e-a556-762fc863b720` |
| `codex_runtime` | UUID | Exactly `ab653716-b90e-40f1-b6ff-5095f818a1f8`; online |
| `copilot_runtime` | UUID | Exactly `05eda9df-e582-43e1-b8e0-3c16f847522d`; online |
| `role_bindings` | map | Team Lead/Planner/Reviewer → Codex; Fullstack/PR Manager → Copilot |
| `legacy_daemon` | UUID | Exactly `019e2a6c-e1d4-737a-afca-e945ec0c8137` |
| `legacy_role_count` | integer | Must be `0` |

### SupervisorBootstrap

| Field | Type | Validation |
|---|---|---|
| `autopilot_id` | UUID | Existing `d67e7307-d0ef-40c4-a597-fd48d73cda48` |
| `agent_id` | UUID | Existing `efc285c0-5c91-4055-80ba-e64b9d6419f9` only |
| `runtime_id` | UUID | Existing NAS runtime `a06e54f0-65cf-46ea-96de-97da512438cf` |
| `trigger_id` | UUID | Existing `52310b59-fd61-4cf7-ae14-523ae55d2a26` |
| `catalog_selection` | tuple | Model, effort, and tier proven supported by that runtime |
| `prior_configuration_identity` | tuple | Redacted prior model/effort/tier plus normalized digest |
| `selected_configuration_identity` | tuple | Redacted selected model/effort/tier plus normalized digest |
| `independent_review` | tuple | Evidence reference, PASS verdict, and matching selected-config digest |
| `rollback_rehearsal` | tuple | Restore/reapply method, timestamp, and passing result while trigger is disabled |
| `probe_run_id` | UUID | Exactly one owner-authorized successful probe |
| `schedule_enabled` | boolean | True only after probe succeeds; false after delivery completes |

### ExternalPRAdoption

| Field | Type | Validation |
|---|---|---|
| `issue_id` | UUID | MY-1540 issue UUID |
| `repository` | URL | Exact VoxPocket repo |
| `delivery_work_dir` | absolute path | Team Lead-provisioned isolated checkout |
| `delivery_branch` | string | Matches checkout metadata |
| `delivery_base_sha` | SHA | Matches checkout metadata |
| `pr_head_base` | tuple | Refreshed from GitHub at handoff time |
| `scope` | string | Existing PR #35 logging candidate; no reimplementation |
| `evidence` | list | Existing checks/tests and remaining gate |

### BenchmarkRun

| Field | Type | Validation |
|---|---|---|
| `group` | enum | Apple, Azure, WhisperKit base, WhisperKit large-v3-turbo, Apple+Azure, Apple+local |
| `verified_model_or_deployment` | string | Factual existing identity; no alias assumption or secret |
| `execution_host` | tuple | Current-Mac daemon/runtime identity and observation time |
| `nas_fixture_read_count` | integer | Must be `0` |
| `nas_fixture_copy_count` | integer | Must be `0` |
| `pacing` | enum | `batch`, `realtime_16_213s` |
| `requested_mode` | enum | `automatic`, `on_device_required`, `not_applicable` |
| `supports_on_device_recognition` | boolean/null | Capability only; null for non-Apple groups |
| `actual_route` | enum | `on_device`, `server`, `unknown`, `not_applicable`; availability is recorded separately |
| `temperature` | enum | `cold`, `warm` |
| `ordinal` | integer | One cold; warm ordinals 1 through 5 |
| `execution_order` | integer | Strict global serial position |
| `process_generation` | string | Fresh process identity for one group/mode |
| `adapter_instance` | enum | `new`, `reused` |
| `engine_instance` | enum | `new`, `reused`, `not_applicable` |
| `model_prepared_before_run` | boolean/null | False for cold, true for warm when a model exists, null otherwise |
| `disk_cache_state` | enum | `present`, `absent`, `not_applicable`; global cache is never cleared |
| `cache_reset_performed` | boolean | Must be false |
| `timings_ms` | map | Download, conversion, model load, request, first partial, stable final after input, total |
| `realtime_factor` | number | Recognition total divided by 16.213 seconds |
| `accuracy` | map | CER, mixed token error rate, punctuation error rate, English `test` preserved |
| `stage_timings_ms` | map | Hybrid final ASR, merger, refinement; null for pure ASR |
| `availability` | enum | `available`, `unavailable`, `unknown` without fallback relabeling |

### BenchmarkReport

| Field | Type | Validation |
|---|---|---|
| `private_path` | absolute directory | Under protected owner benchmark directory only |
| `public_summary` | numeric/label data | Contains no full text, private filenames, secrets, or arbitrary error bodies |
| `individual_runs` | list | Exactly one cold plus five warm per supported group/mode |
| `aggregate` | map | Median and range only; no p95 |
| `recommendation` | string | Case-specific and non-binding |
| `default_changed` | boolean | Must be false |

## Cold/Warm Benchmark Semantics

- A **group/mode** is one provider or hybrid pipeline plus one input pacing mode. Group/mode order is fixed by the validated manifest and recorded in the sanitized summary.
- Before measured runs, audio is decoded exactly once to the canonical mono PCM/WAV input. Conversion time is recorded as preparation and excluded from recognition timings.
- Downloads/cache resolution are preparation. Their duration and the pre-run disk-cache state are recorded, but shared/global caches are never deleted or rewritten to manufacture a cold run.
- A **cold run** is the first measured run for a group/mode in a fresh harness process with new adapter/session/engine instances and no model prepared in that process's memory. Model-load time is recorded separately from recognition-request time.
- The five **warm runs** execute serially in the same process and reuse the cold run's adapter/session/engine and prepared in-memory model. No reinitialization or cache reset occurs between warm runs.
- The harness terminates after one group/mode, then starts a fresh process for the next group/mode. Every run records process generation, adapter/engine reuse, preparation state, disk-cache state, and global execution order.
- Cloud adapters follow the same process/session rules, but in-process model preparation is `not_applicable`; cloud duration includes network. Batch-only adapters record partial/final-after-input metrics as `null`, not zero.

## Relationships

```text
RuntimeOwnership 1──1 DiagnosisEvidence
RuntimeOwnership 1──1 SupervisorBootstrap
CandidateIdentity 1──1 ExternalPRAdoption
ExternalPRAdoption 1──1 DiagnosisEvidence
DiagnosisEvidence 1──1 RepairCandidate
RepairCandidate   1──1 RecoveryProof
RecoveryProof     1──1 ShippingRecord
ShippingRecord    1──1 BenchmarkReport
BenchmarkReport   1──N BenchmarkRun
BenchmarkReport   1──1 InstallRecord
InstallRecord     1──1 TelemetryAcceptance
```

Every downstream record carries or references the upstream exact revision. A head, repair, benchmark-harness, runtime binding, or observer configuration change invalidates the affected downstream review and check evidence.

## State Transitions

```text
READINESS_GAP
  -> RUNTIME_OWNERSHIP_CONFIRMED
  -> DIAGNOSING
  -> OWNER_DECISION_BLOCKED | REPAIR_CANDIDATE
  -> REPAIR_REVIEWED
  -> RECOVERY_PROVED
  -> SUPERVISOR_PROBE_PASSED
  -> SUPERVISOR_SCHEDULE_ENABLED
  -> PR35_EXACT_HEAD_GREEN
  -> PR35_MERGED
  -> BENCHMARK_HARNESS_REVIEWED
  -> BENCHMARK_HARNESS_MERGED
  -> BENCHMARK_ACCEPTED
  -> INSTALL_PREFLIGHT_CONFIRMED
  -> ARCHIVED_AND_BACKED_UP
  -> INSTALLED
  -> TELEMETRY_ACCEPTED
```

Failure after backup transitions to `ROLLBACK_REQUIRED`, then `ROLLED_BACK` or `BLOCKED` with exact evidence. No state transition may skip exact-revision review, merge proof, install preflight, or privacy acceptance.
