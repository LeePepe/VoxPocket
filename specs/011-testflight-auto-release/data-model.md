# Conceptual model: Minimal TestFlight release decision

This feature introduces no product database or serialized user data. It has one persistent workflow datum—the existing last-released Git tag—and otherwise uses run-scoped values.

## Release input

| Field | Meaning |
|---|---|
| `source_event` | `push` or `workflow_dispatch`. |
| `trigger_run_id` / `trigger_run_url` | TestFlight workflow run identity for the automatic push or manual dispatch. |
| `candidate_sha` | Immutable commit selected for checkout and possible release. Automatic value is exactly `github.sha`; manual value is current `main` frozen once. |
| `github_ref` | Automatic admission input; must be `refs/heads/main`. Required PR CI/up-to-date status and App-identity merge are external prerequisites. |
| `marker_sha` | Resolved `testflight/macos-last-released`, or absent for bootstrap. |
| `marker_status` | `absent`, `equal`, `valid-ancestor`, or invalid; invalid status is rejected rather than converted to a release/skip. |
| `changed_paths` | Exact `git diff --name-only marker..candidate` paths when a valid marker exists; for automatic runs, candidate is exactly `github.sha`. |
| `force` | Manual boolean that may bypass only an irrelevant-path result. |

### Invariants

1. Automatic candidates require the `main` push event and checkout equality with `github.sha`; required PR CI/up-to-date enforcement and PR Manager App-identity merge are external delivery prerequisites.
2. Automatic checkout fetches full history so marker resolution, ancestry, and the exact range are locally verifiable.
3. An existing marker must resolve and be an ancestor of the candidate before paths are classified.
4. `candidate_sha == marker_sha` always skips, including manual force.
5. A missing marker is an explicit bootstrap release; an unresolved, corrupt, or non-ancestor marker fails closed.
6. Force cannot change event trust, marker equality/validity, signing, upload, platform, or failure decisions.
7. `testflight/macos-last-released` is the only persistent workflow release state. There is no compare-and-swap record, attempted/skip record, cursor, or reconciliation state.
8. Publication evidence is invalid unless MY-1768 is merged and accepted and the final MY-1765 head descends from the exact `main` revision containing it.
9. The release checkout of AppleUITesting uses and verifies the repository-authoritative full SHA `e6be2fcdf83341a9f3000a4cc489237655461a07`; it cannot consume a moving default branch.

## Classifier result

| Field | Values / meaning |
|---|---|
| `release` | Boolean controlling whether the existing build/upload lane runs. |
| `reason` | `first-release`, `app-relevant-change`, `forced-relevance`, `already-released`, or `no-app-relevant-change`. Invalid marker/trust inputs fail before a release result is consumed. |
| `relevant_paths` | Matching subset of `changed_paths`; empty for bootstrap, equality, or irrelevant range. |

The classifier is a pure production boundary: it receives already resolved marker status and paths, returns a decision or rejects invalid status, and performs no Git/GitHub API call, signing, build, upload, tag mutation, or persistence. Focused unit tests exercise this same classifier rather than a duplicate shadow policy.

## Existing release lane and marker

The existing macOS lane remains the build/upload authority:

- project marketing-version behavior is unchanged;
- App Store Connect build number remains macOS latest plus one;
- the MY-1768 signing/profile repair, existing secrets, package selection, and disabled iOS boundary remain unchanged;
- the release checkout enforces and verifies the existing AppleUITesting full-SHA pin before build work;
- MY-1765 adds no Fastlane field, output, label-based version rule, or Ruby test behavior.

The workflow advances `testflight/macos-last-released` to `candidate_sha` only after upload and all failure-capable cleanup succeed. A skip, pre-marker failure, or determinately rejected marker write leaves the remote marker unchanged. An unconfirmed remote marker push is the sole external ambiguity: it fails the run and exposes ordinary run/SHA evidence for human handling without asserting marker state or creating another persistent state mechanism.

One workflow-level queued concurrency group serializes release and marker handling with `cancel-in-progress: false`. The release job has `contents: read`; only its dependent marker job has `contents: write`. Existing build/signing secrets are step-scoped. Failure-capable `always()` cleanup and action post-steps complete before the marker job may start and block it on failure. The marker update pushes the candidate directly to the remote tag ref without creating new local-tag state and is the final failure-capable state transition; any post-marker reporting/housekeeping is warning-only/non-failing.

## Evidence

| Field | Meaning |
|---|---|
| `implementation_head_sha` | Exact PR head shared by local, review, required-check, and approval evidence. |
| `implementation_base_sha` | Exact post-MY-1768 `main` revision used for final rebase and ancestry proof. |
| `trigger_run_url` / `candidate_sha` | Automatic TestFlight run and exact triggering `main` push SHA. |
| `release_run_url` | Automatic TestFlight workflow run. |
| `marketing_version` / `build_number` | Existing lane's uploaded TestFlight identity. |
| `released_marker_sha` | Post-success marker value, equal to the uploaded candidate. |

Implementation evidence becomes stale after any source push or required MY-1768 rebase. Post-merge evidence cannot be satisfied by classifier fixtures, workflow lint, or the PR head alone.

## Deliberately absent models

There is no source-CI authorization payload, PR-label/version-transition record, CAS token, attempted/skip state, retry state, cursor, reconciliation job, rollback record, shadow-policy result, or rich durable outcome object. D-003/D-005, US3/AC2, US3/AC3, and FR-007 remain traceable as superseded history, not active data requirements.
