# Contract: MY-1540 Recovery Evidence and Handoffs

This contract is the interface between Team Lead, Fullstack Engineer, AI Reviewer, PR Manager, the task-specific observer, and the root coordinator. Values are recorded in a Multica comment or attached sanitized report. Never include secrets, private configuration contents, fixture names, audio, reference text, recognized text, prompts, or arbitrary service error bodies.

## 1. Current-Runtime Ownership Record

Required before repair or dispatch:

```yaml
observed_at_utc: <timestamp>
current_mac_daemon: 019fd055-0738-723e-a556-762fc863b720
roles:
  team_lead: { runtime: ab653716-b90e-40f1-b6ff-5095f818a1f8, provider: codex, online: true }
  planner_lead: { runtime: ab653716-b90e-40f1-b6ff-5095f818a1f8, provider: codex, online: true }
  ai_reviewer: { runtime: ab653716-b90e-40f1-b6ff-5095f818a1f8, provider: codex, online: true }
  fullstack_engineer: { runtime: 05eda9df-e582-43e1-b8e0-3c16f847522d, provider: copilot, online: true }
  pr_manager: { runtime: 05eda9df-e582-43e1-b8e0-3c16f847522d, provider: copilot, online: true }
legacy_daemon: 019e2a6c-e1d4-737a-afca-e945ec0c8137
dev_team_roles_on_legacy_daemon: 0
```

Runtime IDs and daemon IDs, not display names, establish ownership.

## 2. RepoInfra Diagnosis Handoff

```yaml
issue: MY-1540
repository: LeePepe/VoxPocket
feature_pr: 35
base_sha: <40-char SHA>
head_sha: <40-char SHA>
runner_label: macmini-local
runner_service: actions.runner.LeePepe-VoxPocket.macmini-local
runner_root: /Users/tianpli/actions-runner
service_context_verified: true|false
hypotheses:
  lifecycle_sleep_or_offline: { result: supported|rejected|inconclusive, evidence: <redacted> }
  proxy_inheritance: { result: supported|rejected|inconclusive, evidence: <redacted> }
  provider_connectivity_or_auth: { result: supported|rejected|inconclusive, evidence: <redacted> }
  startup_dependency: { result: supported|rejected|inconclusive, evidence: <redacted> }
root_cause: <falsifiable statement>
falsifier: <specific disconfirming observation>
repair_target: [<allowlisted path>]
owner_decision_required: true|false
```

An inconclusive root cause or `owner_decision_required: true` blocks repair.

## 3. Repair and Recovery Handoff

```yaml
repair_kind: host_config|repository
changed_paths: [<exact path>]
before_digests: { <path>: <sha256> }
backup_paths: [<timestamped path>]
after_digest_or_commit: <sha256 or commit SHA>
rollback:
  steps: [<ordered reversible actions>]
  verified: true|false
isolated_failure:
  mechanism: <per-process/test-adapter method>
  global_network_changed: false
  explicit_failure_seconds: <number <= 120>
  fail_closed: true
recovery:
  action: <exact action>
  same_interface_succeeded: true|false
independent_review:
  reviewer: <AI Reviewer evidence>
  verdict: PASS|PASS_WITH_FOLLOW_UP
  reviewed_revision: <must equal after_digest_or_commit>
```

For a tracked repair, also provide the repair PR URL, its required checks, merge SHA, and proof the default branch now contains the trusted repair before refreshing PR #35.

## 4. Existing-Autopilot Bootstrap Handoff

```yaml
autopilot_id: d67e7307-d0ef-40c4-a597-fd48d73cda48
observer_agent_id: efc285c0-5c91-4055-80ba-e64b9d6419f9
runtime_id: a06e54f0-65cf-46ea-96de-97da512438cf
trigger_id: 52310b59-fd61-4cf7-ae14-523ae55d2a26
previous_failures:
  - <run id and sanitized unsupported-model classification>
runtime_catalog_observed_at_utc: <timestamp>
selected_model: <catalog-valid identifier>
selected_effort: <catalog-valid value or inherited>
selected_service_tier: <catalog-valid value or inherited>
shared_agents_changed: false
probe_run_id: <id>
probe_status: succeeded
probe_scope_verified: observe_dispatch_bounded_rerun_report_only
schedule: { cron: '*/10 * * * *', timezone: Asia/Shanghai, enabled: true }
disable_after_delivery: pending|complete
```

Only the existing observer agent may receive this configuration. Do not move Dev Team roles, create another autopilot, or use trial-and-error model updates as catalog discovery.

## 5. External PR #35 Adoption and Shipping Handoff

```yaml
issue_id: cba19180-e28c-46ce-afb2-af26a22528da
issue_key: MY-1540
repository: https://github.com/LeePepe/VoxPocket
delivery_work_dir: <Team Lead isolated checkout>
delivery_branch: <branch>
delivery_base_sha: <SHA>
feature_pr: https://github.com/LeePepe/VoxPocket/pull/35
pre_refresh_head_sha: 6066a66ceaa52ddedc74136352913f70daa9e160
current_base_sha: <SHA>
current_head_sha: <SHA after any base refresh>
scope: existing_logging_candidate_only
evidence: <existing tests/reviews summary>
required_checks:
  SPM_VoxDomain: <success URL>
  SPM_VoxInfrastructure: <success URL>
  SPM_VoxApplication: <success URL>
  SPM_VoxPresentation: <success URL>
  SPM_VoxUITesting: <success URL>
  App_target: <success URL>
  Lint_and_policy: <success URL>
  codex_review_target: <success URL bound to current_head_sha>
merge_mechanism: repository_auto_squash
state: MERGED
merged_at_utc: <timestamp>
feature_merge_sha: <SHA>
remote_main_sha: <SHA containing feature_merge_sha>
```

The author identity is irrelevant to adoption. Kimi advisory status is not the required Codex verdict.

## 6. Benchmark Handoff

### Private report

The full report remains under:

```text
/Users/tianpli/Library/Containers/com.leepepe.voxpocket/Data/Library/Application Support/VoxPocket/benchmarks/owner-20260910/
```

It may contain reference/recognized text but must remain owner-only (directory mode 0700; report files 0600), excluded from Git, and never be copied to NAS or attached to the issue.

### Public sanitized summary

```yaml
benchmark_pr: <separate reviewed PR URL>
benchmark_head_sha: <exact reviewed SHA>
benchmark_merge_sha: <merged SHA>
manifest_path_class: protected_app_sandbox # never basename/private child paths
fixture_duration_seconds: 16.213
input_identity: <non-reversible digest>
execution: { serial: true, cold_runs: 1, warm_runs: 5 }
groups:
  - label: <approved provider or hybrid label>
    verified_model_or_deployment: <non-secret factual label>
    availability: available|unavailable|unknown
    pacing: batch|realtime_16_213s
    runs:
      - ordinal: cold|warm-1|warm-2|warm-3|warm-4|warm-5
        download_ms: <number|null>
        conversion_ms: <number|null>
        model_load_ms: <number|null>
        request_ms: <number|null>
        first_partial_ms: <number|null>
        stable_final_after_input_ms: <number|null>
        total_ms: <number|null>
        realtime_factor: <number|null>
        cer: <number|null>
        mixed_token_error_rate: <number|null>
        punctuation_error_rate: <number|null>
        english_test_preserved: true|false|null
        stages: { final_asr_ms: <number|null>, merger_ms: <number|null>, refinement_ms: <number|null> }
    summary: { median: <numeric map>, range: <numeric map> }
cloud_time_includes_network: true
reference_was_not_model_input: true
pure_asr_refinement_disabled: true
public_private_field_violations: 0
recommendation: <case-specific statement or no recommendation>
default_model_changed: false
```

Do not publish recognized/reference text, private filenames, secrets, arbitrary error bodies, or p95 claims.

## 7. Root-Coordinator Validation and Install Handoff

Required preconditions: PR #35 and the benchmark-harness PR are merged; runtime/runner/autopilot evidence above is complete; the root coordinator acknowledges exclusive ownership of the primary checkout and install surface.

```yaml
source:
  primary_checkout: /Users/tianpli/Development/VoxPocket
  remote_main_sha: <SHA>
  local_head_sha: <same SHA>
  feature_merge_sha: <SHA>
  benchmark_merge_sha: <SHA>
  lokikit_sha: eff9c1712cd648ed0717e41183ad8bd7bf39cbea
  dirty_state: <verbatim path list summary; preserved, not cleaned>
candidate_validation:
  benchmark_summary_ref: <sanitized evidence>
  private_report_directory: <protected directory only>
  real_app_log_query: '{app="VoxPocket",stream="log"} |= "Local log collection started"'
  candidate_log_count: <integer >= 1>
archive:
  path: <new timestamped .xcarchive>
  app_path: <archive>/Products/Applications/VoxPocket.app
  private_config_bundle_guard: pass
pre_install:
  old_app_path: /Applications/VoxPocket.app
  recording: false
  unsaved_text: false
  confirmation_source: <owner-visible check, no content>
  backup_path: <timestamped app backup>
install:
  installed_app_path: /Applications/VoxPocket.app
  running_instances: 1
  sandbox_data_preserved: true
  preferences_preserved: true
  private_model_config_preserved: true
post_install_acceptance:
  action: startup_and_harmless_window_operation
  query: '{app="VoxPocket",stream="log"}'
  start_utc: <timestamp>
  end_utc: <timestamp>
  record_count: <integer >= 2>
  grafana_url: http://localhost:3010/d/voxpocket-logs
  grafana_ready: true
  forbidden_content_count: 0
rollback:
  backup_retained: true
  status: available|executed
supervisor_schedule_disabled_after_acceptance: true
```

If the old app is recording or has unsaved text, stop and ask before quitting. Any missing exact SHA, backup, private-config guard, real-app record, or privacy result blocks completion.
