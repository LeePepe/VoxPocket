# Validation Quickstart: MY-1540

This is an ordered verification guide, not authorization to skip task dependencies. Use the exact evidence schema in [contracts/recovery-evidence.md](./contracts/recovery-evidence.md). Never print secret values, benchmark text, private filenames, or arbitrary service error bodies.

## 0. Preconditions

- Work only from Team Lead's isolated delivery checkout until the root-coordinator handoff.
- Confirm the five Dev Team role bindings use the current-Mac daemon IDs in the contract.
- Keep legacy daemon `019e2a6c-e1d4-737a-afca-e945ec0c8137` unused.
- Keep autopilot trigger `52310b59-fd61-4cf7-ae14-523ae55d2a26` disabled until the observer probe succeeds.
- Do not read or copy the owner benchmark fixture from the NAS observer.

## 1. Capture live identities

```bash
multica runtime list --output json
multica agent get efc285c0-5c91-4055-80ba-e64b9d6419f9 --output json
multica autopilot get d67e7307-d0ef-40c4-a597-fd48d73cda48 --output json
multica autopilot runs d67e7307-d0ef-40c4-a597-fd48d73cda48 --output json
gh pr view 35 --repo LeePepe/VoxPocket --json state,headRefOid,baseRefOid,mergeStateStatus,autoMergeRequest,statusCheckRollup
```

Expected: current-Mac Codex and Copilot runtimes are online; no Dev Team role is on the legacy daemon; the observer is on its existing NAS runtime; its trigger is disabled; PR #35 is open and blocked only by the required Codex check before recovery.

## 2. Diagnose and verify runner recovery

Use the service-context procedure selected by the diagnosis task. Record only status codes, timing, boolean reachability/auth results, and redacted error classes. Compare:

1. LaunchAgent/runner lifecycle before and after sleep/network recovery.
2. Required proxy-variable presence/absence in the service context versus an interactive shell, without recording values.
3. TCP/TLS reachability and the authenticated Codex review path from the service context.
4. Startup with optional MCP/hooks disabled as already configured, distinguishing startup dependency from model execution.

Inject failure only into a disposable review process/test adapter. Require explicit fail-closed output within 120 seconds, then restore and run the same interface successfully. Verify backup checksums before and after rollback rehearsal.

For any tracked repair:

```bash
python3 scripts/gates/check_frontmatter.py
zsh scripts/docs/lint_docs_map.sh
zsh scripts/docs/lint_docs_freshness.sh
bash scripts/ci/tests/test_codex_review_preflight.sh
```

The focused test command applies only if diagnosis selects a repository repair and creates that test. Merge the reviewed repair PR to `main` before refreshing PR #35.

## 3. Bootstrap the existing supervisor

Inspect the NAS runtime's supported model/effort/service-tier catalog using its authoritative runtime surface. Choose a supported tuple; do not infer it from old usage records or trial-and-error writes. Update only observer `efc285c0-5c91-4055-80ba-e64b9d6419f9`, run one explicit authorized probe, then verify:

- probe status is `succeeded`;
- output has one bounded observation/action and no implementation/config mutation;
- the existing `*/10` trigger is enabled;
- no additional autopilot/trigger was created.

If the probe fails, leave the trigger disabled and return the sanitized error to Team Lead.

## 4. Adopt and ship external PR #35

Before PR Manager acts, compare Team Lead's delivery workspace metadata with GitHub's live base/head. If a tracked repair changed `main`, update PR #35 under normal Git rules and recapture its head.

```bash
gh pr checks 35 --repo LeePepe/VoxPocket --required
gh pr view 35 --repo LeePepe/VoxPocket --json state,headRefOid,baseRefOid,mergeCommit,mergedAt,mergeStateStatus,autoMergeRequest,statusCheckRollup
git ls-remote https://github.com/LeePepe/VoxPocket.git refs/heads/main
```

Expected: all eight required contexts, including a real `codex-review-target`, pass on the same exact head; auto-squash merges PR #35; remote `main` contains the GitHub-reported merge SHA. Do not treat Kimi advisory as the required review.

## 5. Validate and ship the benchmark harness

In the isolated benchmark branch, verify a Packages-only diff before testing:

```bash
git diff --name-only origin/main...HEAD
swift build --package-path Packages/VoxInfrastructure
swift test --package-path Packages/VoxInfrastructure
```

No `xcodebuild` is permitted for a Packages-only benchmark diff. Independently review and merge this as a separate PR.

On the current Mac, set only the approved opt-in variables and invoke the dedicated live-test target. The isolated delivery checkout must first have its task-local LokiKit sibling pinned to the published revision; do not use or mutate a global cache to work around a missing dependency.

```bash
VOX_ENABLE_OWNER_BENCHMARK=1 \
VOX_BENCHMARK_MANIFEST='/Users/tianpli/Library/Containers/com.leepepe.voxpocket/Data/Library/Application Support/VoxPocket/benchmarks/owner-20260910/manifest.json' \
swift test --package-path Packages/VoxInfrastructure \
  --filter ApprovedOwnerBenchmarkTests/testOwnerFixture
```

Expected: full text remains under the manifest root in `results/<UTC>-<git-sha>/private-report.json`; `summary.json` and stdout contain sanitized numeric/label data only. Validate one cold plus five warm serial runs per supported provider/pipeline and pacing mode, median/min/max only, separate stage timings for hybrids, and explicit unavailable/unknown rows rather than fallback relabeling.

## 6. Root-coordinator candidate validation and archive

Only the root coordinator may use `/Users/tianpli/Development/VoxPocket`. Preserve its unrelated untracked paths and record them without cleaning. Synchronize to the final remote `main` containing both merge SHAs and verify LokiKit at `eff9c1712cd648ed0717e41183ad8bd7bf39cbea`.

Build a new archive using the repository command:

```bash
MY1540_BUILD_STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$(git rev-parse --short HEAD)"
xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket \
  -configuration Debug -destination 'generic/platform=macOS' \
  -archivePath "build/local/VoxPocket-${MY1540_BUILD_STAMP}.xcarchive" archive
```

Require the new `.xcarchive/Products/Applications/VoxPocket.app` and run the repository private-config bundle guard. Before replacing the installed app, confirm it is not recording and has no unsaved text. If either is uncertain, ask the owner.

Quit the old app gracefully, keeping `/Applications/VoxPocket.app` unchanged on disk, then launch the archive app alone for candidate log validation. Record a UTC start time, wait longer than the two-second sink interval, and query the safe marker:

```bash
curl --fail --silent --show-error --get 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={app="VoxPocket",stream="log"} |= "Local log collection started"' \
  --data-urlencode 'start=<UTC-nanoseconds>' \
  --data-urlencode 'end=<UTC-nanoseconds>'
```

Stop the candidate after proof. If it fails, reopen the unchanged installed app and do not install.

## 7. Back up, install, and accept

After candidate validation, create a timestamped backup of `/Applications/VoxPocket.app` without deleting it. Replace it with the validated archive app, launch exactly one instance, and verify sandbox data, preferences, and private model configuration remain available without printing their contents.

Perform startup plus one harmless window show/hide action. Query the five-minute acceptance window for `{app="VoxPocket",stream="log"}`, require startup and window records, and check `http://localhost:3010/d/voxpocket-logs`. Inspect all returned message/context fields for forbidden content categories.

On any failure, stop the new app, move it aside, restore the exact backup, and relaunch the backup only if it was previously running. Retain all archives and the backup.

## 8. Closeout

Post the complete recovery/benchmark/install/telemetry evidence contract. Only after Team Lead verifies it, disable the existing task-specific schedule and record `disable_after_delivery: complete`. Do not delete the autopilot.
