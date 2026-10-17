# Requirements checklist: Privacy-safe Azure Blob product telemetry

**Purpose**: Confirm the specification is complete, testable, privacy-safe, and ready for independent spec-gate review.

**Created**: 2026-10-15
**Feature**: [`../spec.md`](../spec.md)

## Intent and scope

- [x] CHK001 Accepted intent is pinned to MY-1818 issue revision 1 and the repository baseline.
- [x] CHK002 In-scope and non-goal boundaries distinguish repository delivery from Owner-controlled production proof.
- [x] CHK003 Existing behavior, compatibility, rollback, and all intentional behavior changes are explicit, including legacy off-main execution and provider-default bounded retention.
- [x] CHK004 Real cloud identifiers and credentials are excluded from committed planning artifacts.

## Acceptance quality

- [x] CHK005 Every user story has stable `US#/AC#` identifiers and an independent test.
- [x] CHK006 Functional requirements are uniquely numbered and use testable MUST/MUST NOT language.
- [x] CHK007 Success criteria include measurable privacy, disabled-state, Release-expansion, regression, PR-gate, and production outcomes.
- [x] CHK008 Edge cases cover partial/unexpanded config, invalid policy data, concurrent legacy/Blob lifecycle work, cancellation, tag timing, synthetic Release, missing Owner authority, capacity eviction, and cleanup-before-rollback.

## Privacy and secrets

- [x] CHK009 The product vocabulary is exactly two typed events; heartbeat ownership is distinguished.
- [x] CHK010 Prohibited voice/text/error/credential data and whole-event rejection are explicit.
- [x] CHK011 Existing arbitrary error telemetry has authority, owning boundaries, regressions, and removed-behavior analysis.
- [x] CHK012 Missing config performs no identity/store/network work; invalid present config fails only Blob closed.
- [x] CHK013 Real values enter only the authorized TestFlight archive through a runner-temp untracked `0600` xcconfig; only its path reaches `-xcconfig`, cleanup is unconditional, and synthetic Release proof is credential-free/non-networked.
- [x] CHK021 Raw and shell/percent-escaped synthetic sentinel forms are both required absent from Release-path logs, arguments, and messages.
- [x] CHK022 Decision 1A is exact: key-auth stored policy with permission `c`/explicit expiry, HTTPS-only `--policy-name` service SAS, supported query names, stored-policy `sp` omission, and no user-delegation fields.
- [x] CHK026 The common consent contract is exact: persisted “Send usage data” defaults off, disable stops admission/upload without host/manual deletion while retaining non-evicted pending files plus any persisted UUID, provider-owned capacity eviction remains allowed, and only a later explicit opt-in resumes.
- [x] CHK027 Install identity is random and provisioned only by eligible interactive-app composition after explicit consent is persisted; missing/invalid configuration and excluded hosts retain consent with no identity request/creation. The UUID is retained across disable without active-service use, reused after every later opt-in and eligible launch for the app installation's lifetime, has no v1 Reset/rotation surface, requires no shared-telemetry API change or private-storage parsing, and is never exposed as a product property or evidence value.
- [x] CHK031 T009 owns an additive consent-only preference interface and focused Infrastructure proof while preserving the accepted T008 coupled provisioning behavior and tests.

## Architecture and delivery

- [x] CHK014 Loki event/log paths and stores remain separate from Blob routing and storage.
- [x] CHK015 Legacy provider construction/every active `track`/`flush` plus Blob construction/product `track`/lifecycle `flush` are confined to one shared app-lifetime coordinator backed by a dedicated serial non-main executor; Decision 2A exempts only SDK-owned internally synchronized off-main heartbeat work.
- [x] CHK016 Dependency tag/SHA selection, the complete active authority/projection set, deliberate constitution amendment, historical-evidence exclusion, and recheck timing are explicit.
- [x] CHK017 XcodeGen truth, CODEOWNERS/Owner gates, manual release semantics, and exact-head publication rules are preserved per single-goal PR.
- [x] CHK018 Each acceptance/requirement has a planned task and evidence surface; external Owner work is separately blocked.
- [x] CHK023 The current delivery topology follows the canonical `tasks.md` graph: PR01 is the required-CI slice; atomic PR02 combines the exact-`0.2.0` dependency/current-truth migration with the off-main runtime adaptation in one slice with no standalone PR03; privacy, dormant runtime, app adoption, synthetic CI, and TestFlight governance remain independently working slices, and each step leaves `main` working.
- [x] CHK024 Every PR has focused verification plus `scripts/verify`, exact-tree review/publication evidence, local/remote/PR SHA equality, stacking/rebase rules, and applicable Owner gates.
- [x] CHK028 CLI, headless, and test hosts have an explicit zero-construction contract and credential-free fixtures, while only the interactive app composition root may construct after configuration plus consent; no production CLI target is invented for the proof.
- [x] CHK029 A main-actor-originating test proves provider construction, ordered legacy tracks, and barrier flush all reach the underlying spy with `Thread.isMainThread == false` and maximum concurrency one; a structural assertion rejects raw-provider bypass.
- [x] CHK030 The plan and migration/rollback notes intentionally accept the pinned provider's 50 MiB default, whole-oldest-batch eviction, oversized-event rejection, durable loss accounting, cleanup-before-downgrade rule, and irrecoverable evictions, with no `maxDiskBytes` override.
- [x] CHK032 Rapid-release and startup/recording/session/resign-active regressions drive the real `AppDelegate` / `ServiceContainer` callers; direct instrumentation tests are supplemental rather than substitutes.
- [x] CHK033 The iOS persisted-consent cold-start increment is lifecycle-owned, invokes the existing startup adapter only after successful shared configuration preparation, proves relaunch UUID reuse and one startup event/flush per lifetime without sleep, binds the actual conditional caller, and leaves macOS/default-off/fail-closed/excluded-host behavior unchanged.

## Review readiness

- [x] CHK019 No unresolved `[placeholder]`, `NEEDS CLARIFICATION`, or invented credential/resource value remains.
- [x] CHK020 `spec.md`, `plan.md`, `research.md`, `data-model.md`, contract, quickstart, checklist, and layer-scoped `tasks.md` form one consistent design.
- [x] CHK025 All 23 stable AC IDs, FR-001–FR-028, SC-001–SC-010, RB-001–RB-005, and T000–T013 are covered without a placeholder, stale no-behavior-change claim, stale consent contradiction, stale singular-PR contract, or unresolved prior finding.

## Notes

- A check mark means the planning artifact contains the requirement; it does not claim implementation or production delivery.
- Any spec-gate finding reopens the owning artifact and requires a new exact planning revision.
