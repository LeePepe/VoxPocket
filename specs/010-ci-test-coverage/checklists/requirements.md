# Specification quality checklist: CI test coverage

**Purpose**: validate the specification before planning/review  
**Created**: 2026-10-13  
**Spec**: [`../spec.md`](../spec.md)

## Content quality

- [x] Actors, observable outcome, constraints, and non-goals are explicit.
- [x] Stable acceptance IDs are append-only and independently testable.
- [x] Existing behavior, compatibility, and removed behavior are separate complete sections.
- [x] Every removal/test-contract change cites D-002 and the required Owner approval.
- [x] No unresolved `NEEDS CLARIFICATION` remains.

## Requirement completeness

- [x] All issue acceptance criteria map to US1–US4.
- [x] TestFlight behavior/message and iOS release prohibition are explicitly preserved.
- [x] zsh, Xcode unit/UI, and test-executor dispositions are deterministic.
- [x] The four pre-existing required root-policy tests are inventoried and protected by US4/AC4, authoritative contract rows, T006, and T010.
- [x] UI manual evidence is explicitly not applicable, with automated evidence form named.
- [x] Failure/empty-discovery, secrets, platform-skip, and CI-session edge cases are covered.
- [x] Generic shared-ci orphan policy and SPM layout are out of scope.

## Readiness

- [x] Required-check names and exact-SHA evidence requirements are explicit.
- [x] Layer/support-scope ownership and the T001→T003 support/gate contract edge are defined in the plan/contract.
- [x] Unknown Xcode feasibility is isolated as a CI checkpoint with a bounded escalation rule.
- [x] No product/content/authority decision is invented.

**Result**: PASS for Plan/Tasks generation; independent AI Reviewer gate still required.
