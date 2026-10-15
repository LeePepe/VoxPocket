# TestFlight automatic release contract

## Trigger contract

| Entry | Required admission | Candidate SHA |
|---|---|---|
| `push` | `branches: [main]`; event ref is `refs/heads/main` | exactly `github.sha` |
| `workflow_dispatch` | macOS manual fallback; boolean `force`; current repository | current `main` HEAD, frozen once |

Automatic checkout uses `fetch-depth: 0` and verifies checked-out `HEAD == github.sha`. Required PR CI against an up-to-date branch and PR Manager App-identity merge are external delivery prerequisites; this workflow does not poll CI, call merge APIs, or request permissions for them. All event/ref/candidate checks occur before secret-bearing, signing, build, upload, or marker-write steps.

The release workflow also checks out `LeePepe/AppleUITesting` with `ref: e6be2fcdf83341a9f3000a4cc489237655461a07` and verifies that checkout's `HEAD` equals the full SHA before build work. This enforces the existing repository pin used by CI; it does not change the dependency revision.

## Relevant path contract

When `testflight/macos-last-released` exists and is a valid ancestor of the candidate, changed paths are exactly:

```sh
git diff --name-only "${marker}..${candidate}"
```

For an automatic run, `candidate` is exactly `github.sha`, so the release decision is over exactly `marker..github.sha`. For a manual run it is the once-frozen current `main` SHA.

The candidate is app-relevant when at least one changed path matches:

```text
Packages/**
VoxPocket/**
VoxPocketWidget/**
fastlane/**
.github/workflows/testflight.yml
scripts/ci/fetch-external-deps.sh
```

`docs/**`, `specs/**`, other `.github/**`, and unrelated support paths are not implicit matches. Mixed diffs release. Manual `force` may bypass only the no-match result. With no marker, there is no trusted diff baseline, so the candidate is an explicit bootstrap release.

The production classifier accepts the frozen candidate, resolved marker status, exact changed-path list when applicable, and force input. It returns the release/skip decision or rejects invalid marker status. It does not run Git resolution/diff, query GitHub, mutate a tag, sign, build, upload, or persist state.

## Eligibility decision table

Evaluate in table order; the first matching terminal condition wins.

| Condition | Result |
|---|---|
| Automatic event is not the admitted `main` push or checkout differs from `github.sha` | fail closed; no secret-bearing work |
| Marker exists but cannot resolve or is not an ancestor of candidate | fail closed |
| Candidate equals marker | skip (`already-released`); force ignored |
| Marker is absent and other admission checks pass | release (`first-release`); relevance is not evaluated |
| At least one relevant path exists | release (`app-relevant-change`) |
| No relevant path and manual force is true | release (`forced-relevance`) |
| No relevant path otherwise | skip (`no-app-relevant-change`) |

A skip performs no signing, build, upload, or marker write. The irrelevant-path case writes a concise non-secret reason summary; ordinary workflow logs remain the run evidence.

## Existing build/upload contract

- The existing macOS Fastlane build/upload lane is invoked unchanged after an eligible decision.
- Project marketing-version authority and behavior remain unchanged.
- Build number remains the current macOS App Store Connect latest build across all versions plus one.
- Existing upload/package inputs and secret names remain unchanged.
- The separately accepted MY-1768 signing/profile repair remains unchanged. The AppleUITesting dependency value remains pinned to `e6be2fcdf83341a9f3000a4cc489237655461a07`; MY-1765 makes the release checkout consume and verify that existing pin.
- The iOS lane stays disabled and cannot be selected.
- No label lookup, associated-PR lookup, semantic-version transition policy, Fastlane output addition, Ruby packaging behavior change, or new test path is part of MY-1765. The existing packaging contract test is narrowly adapted only for the accepted force/job-boundary/authenticated-marker contract.

## Runtime, permission, and cleanup contract

- Publication prerequisite: MY-1768 is separately accepted and merged; the final MY-1765 head descends from the exact `main` revision containing it, and every exact-head artifact and verdict is regenerated after that rebase.
- Runner: `[self-hosted, macOS, ARM64]`.
- One VoxPocket macOS concurrency group covers evaluation through marker handling; `cancel-in-progress: false`.
- Release-job token permission is exactly `contents: read`; only the dependent marker job has `contents: write`. No `actions: read`, `pull-requests: read`, or broader permission is needed.
- Existing ASC and signing secret names are exposed only on the build/signing steps that require them.
- Failure-capable `always()` cleanup removes temporary keychain/local-tag state before marker advancement after success, skip, or failure. It preserves an earlier failure, and its own failure after an otherwise successful upload fails the job and blocks the marker write.
- The marker write pushes the exact candidate directly to the remote tag ref without creating a new local tag and is the final failure-capable state transition. Any post-marker reporting/housekeeping is explicitly best-effort/non-failing and emits a warning on failure; it cannot turn the successful run into a failed run with an advanced marker.

## Marker and failure contract

- `testflight/macos-last-released` is the sole persistent workflow release state.
- After upload and all failure-capable cleanup succeed, move the marker to the exact candidate SHA.
- A skip or any failure before the marker attempt leaves the remote marker unchanged; a determinately rejected marker write also leaves it unchanged.
- A remote marker push whose result cannot be confirmed is the sole external ambiguity. It fails the run and exposes the run URL, candidate SHA, and ordinary upload/tag logs for human handling without asserting whether the remote marker moved.
- No CAS boundary, per-SHA attempted/skip record, cursor, retry, rollback, reconciliation, alternate SHA, marker rollback, or fallback release is created.
- A later distinct eligible `main` push or explicit manual dispatch performs a fresh evaluation from the then-current sole marker; it never resumes a stored cursor or failed attempt.

## Verification contract

- Focused Python unit tests invoke the production classifier directly and cover exact path matches, mixed and irrelevant ranges, absent-marker bootstrap, marker equality, invalid/non-ancestor rejection, and relevance-only force.
- The existing workflow-freshness and packaging contract tests cover `push`/`github.sha`, manual force, least-privilege job permissions, cleanup, and terminal authenticated marker handling. Repository workflow lint validates the changed workflow. There is no new test path or feature-specific shadow-policy suite.
- Normal repository verification and required checks remain unchanged and bind to one exact implementation PR head.
- No Fastlane/Ruby behavior changes or feature-specific Ruby test additions are authorized.
- MY-1768 merge SHA, accepted manual release URL/build, exact containing-`main` base SHA, and ancestry proof are required before publication evidence is accepted; the rebase invalidates all earlier artifacts and verdicts.
- A real post-merge automatic run alone satisfies US4/AC4.

## Canonical repository-rule contract

- Update `Last-Reviewed` and narrowly update the TestFlight delivery wording in `AGENTS.md` to authorize automatic CD for the exact `main` push SHA under D-001/D-010/D-012.
- Retain manual `workflow_dispatch` as fallback, protected-path Owner approval/CODEOWNER enforcement, TestFlight-only delivery, and separate Owner authorization for iOS releases.
- No other `AGENTS.md` rule or repository policy changes.

## Traceability contract

- US1/AC1, US1/AC2, US1/AC3, US1/AC4, FR-001, and FR-002: push admission, exact `github.sha` candidate, full-history checkout, and trigger evidence.
- US2/AC1, US2/AC2, US2/AC3, US2/AC4, US2/AC5, FR-003, FR-004, and FR-005: marker validity/equality, exact path classification, bootstrap, and relevance-only force.
- US3/AC1, US3/AC4, US3/AC5, FR-006, FR-008, FR-009, FR-010, and FR-011: unchanged release lane, MY-1768 prerequisite, queued concurrency, permission/secrets/cleanup, successful-upload marker movement, and failure boundary.
- US3/AC2, US3/AC3, and FR-007: superseded history only; no implementation behavior is authorized.
- US4/AC1, US4/AC2, US4/AC3, US4/AC4, and FR-012: focused local verification, exact-head protected delivery, and real post-merge outcome.
