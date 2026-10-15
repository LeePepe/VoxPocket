# Requirements checklist: Privacy-safe Azure Blob product telemetry

**Purpose**: Confirm the specification is complete, testable, privacy-safe, and ready for independent spec-gate review.

**Created**: 2026-10-15
**Feature**: [`../spec.md`](../spec.md)

## Intent and scope

- [x] CHK001 Accepted intent is pinned to MY-1818 issue revision 1 and the repository baseline.
- [x] CHK002 In-scope and non-goal boundaries distinguish repository delivery from Owner-controlled production proof.
- [x] CHK003 Existing behavior, compatibility, rollback, and intentionally removed behavior are explicit.
- [x] CHK004 Real cloud identifiers and credentials are excluded from committed planning artifacts.

## Acceptance quality

- [x] CHK005 Every user story has stable `US#/AC#` identifiers and an independent test.
- [x] CHK006 Functional requirements are uniquely numbered and use testable MUST/MUST NOT language.
- [x] CHK007 Success criteria include measurable privacy, disabled-state, Release-expansion, regression, PR-gate, and production outcomes.
- [x] CHK008 Edge cases cover partial/unexpanded config, invalid policy data, concurrent lifecycle work, cancellation, tag timing, synthetic Release, missing Owner authority, and rollback files.

## Privacy and secrets

- [x] CHK009 The product vocabulary is exactly two typed events; heartbeat ownership is distinguished.
- [x] CHK010 Prohibited voice/text/error/credential data and whole-event rejection are explicit.
- [x] CHK011 Existing arbitrary error telemetry has authority, owning boundaries, regressions, and removed-behavior analysis.
- [x] CHK012 Missing config performs no identity/store/network work; invalid present config fails only Blob closed.
- [x] CHK013 Real values enter only the authorized TestFlight archive; synthetic Release proof is credential-free and non-networked.

## Architecture and delivery

- [x] CHK014 Loki event/log paths and stores remain separate from Blob routing and storage.
- [x] CHK015 Synchronous adapter I/O is confined to one serialized non-`@MainActor` coordinator.
- [x] CHK016 Dependency tag/SHA selection, repository-wide consistency, and recheck timing are explicit.
- [x] CHK017 XcodeGen truth, CODEOWNERS/Owner gates, manual release semantics, and exact-head publication rules are preserved.
- [x] CHK018 Each acceptance/requirement has a planned task and evidence surface; external Owner work is separately blocked.

## Review readiness

- [x] CHK019 No unresolved `[placeholder]`, `NEEDS CLARIFICATION`, or invented credential/resource value remains.
- [x] CHK020 `plan.md`, `research.md`, `data-model.md`, contract, quickstart, and layer-scoped `tasks.md` form one consistent design.

## Notes

- A check mark means the planning artifact contains the requirement; it does not claim implementation or production delivery.
- Any spec-gate finding reopens the owning artifact and requires a new exact planning revision.
