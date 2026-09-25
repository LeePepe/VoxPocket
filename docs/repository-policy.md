# Repository review policy

Last-Reviewed: 2026-09-25

This is the repository-specific policy supplied as text to both reusable AI reviewers
from the trusted base checkout. Links provide detail; following them is not required to
apply the rules below. The [constitution](../.specify/memory/constitution.md) remains the
authority for its principles; privacy/configuration bullets below project those principles
into the review boundary. Architecture ownership remains in the layer contexts.

## Scope and integrity

- One task uses one dedicated branch/worktree and one PR based on the default branch,
  with one writer. Preserve unrelated work and existing local artifacts.
- Read the constitution, root architecture context and touched layer contexts before edits.
  Split changes spanning two or more layers. Fix failures within the failing layer and its
  red lines; a root cause in another layer is a new task. Dependencies point down only.
- Existing product behaviour and UX stay unchanged without an approved spec.
  `VoxPocket/project.yml` is the Xcode project source of truth.
- Run `scripts/verify` before push. Do not bypass hooks, skip or weaken tests/assertions to
  make failures pass, or edit policy/gates/schema/CI just to pass. An incorrect gate needs
  a separately justified, Owner-reviewed change. Pin shared libraries by full SHA or exact
  version; the shared-ci protocol pointer must equal the reusable workflow pins.

## Review and execution boundaries

Owner decision (2026-09-25): ordinary in-scope test-code edits or deletions require no
Owner approval, including execution of a test-only plan. Explain removed, skipped or
weakened tests/assertions, their reasons and retained/replacement coverage in the PR;
this permission does not relax the integrity rule above. It supersedes test-only approval
wording in sections 4 and 6 of the older pinned shared-ci protocol.

Every implementation plan, spec or plan change still follows independent AI Plan-Review:

1. A planner creates or updates the plan/spec.
2. An independent reviewer reviews it immediately.
3. The planner fixes CRITICAL or MEDIUM findings.
4. The reviewer re-reviews without waiting to be asked.
5. Repeat until the reviewer outputs `APPROVED` with no CRITICAL finding.
6. After AI approval, ordinary in-scope test maintenance proceeds without an Owner
   execution hold. For other implementation plans, obtain Owner execution approval.

This is not an exemption from the AI loop. Policy, gate, schema, ruleset, permission,
credentials, privacy, data migration and other protected changes still need Owner review;
ordinary test permission does not authorize changing those controls. The
[CODEOWNERS map](../.github/CODEOWNERS) covers important paths, including policy-enforcing
tests. Workflows, hooks, `scripts/verify`, architecture contexts, AGENTS, the constitution
and dependency pins are important changes; add `owner-review`. Other approved exceptions: none.

## Privacy and configuration

- Recorded audio, transcripts and refined text stay inside the app sandbox and never enter
  logs or telemetry payloads. Telemetry contains only durations, counts, source labels and
  session IDs, never user content (constitution IV).
- Secrets come from environment variables, not source. Azure credentials may also use the
  runtime-only sandbox `config.private.json`: an owner-only regular file (0600), excluded
  from backups, Git and app bundles. Never log its contents or decoder errors; commit only
  the empty `config.example.json` template (constitution V).
- No real Microsoft/Azure resource identifiers, endpoints, tenant IDs or other non-public
  project values in code, tests, fixtures or docs. Use synthetic `example-*` values and
  gitignored local files with committed empty templates for real configuration.
- No credentials, personal account names, credential-profile paths or local home paths in
  repository files. Existing CODEOWNERS ownership metadata is not permission to copy identity
  information into other files. Detailed configuration remains in
  [private model configuration](architecture/private-model-config.md).

## App delivery boundary

Every user-facing macOS/iOS App build is TestFlight-only, through
`.github/workflows/testflight.yml` with manual `workflow_dispatch` after an explicit Owner
request. Agents do not create local delivery archives, install, replace or launch delivery
builds, or sign in to App Store Connect. Upload success is not "testable"; the Owner verifies
availability and testability. macOS is released via TestFlight; iOS development/CI remains
enabled, but iOS TestFlight needs separate Owner authorization. Local package tests and
unsigned CI builds are verification, not delivery.

## Required checks

These names must equal the live `main protection` ruleset, mirrored in
[`main-protection.json`](../scripts/rulesets/main-protection.json):

- `quality / aggregate`
- `codex-review-target / codex-review`
- `SPM VoxDomain`
- `SPM VoxInfrastructure`
- `SPM VoxApplication`
- `SPM VoxPresentation`
- `SPM VoxUITesting`
- `App target`
- `Lint & policy`

CODEOWNERS review is required (0 extra approvals); stale reviews are dismissed on push.
The branch need not be up to date (`strict` off): Owner-approved R3 (2026-09-24) relies on
`quality / aggregate` requiring every lane to pass on the PR head SHA and a complete PR body.
Every new push invalidates prior verification/review. Done means required checks are green
on that head, not a local pass. The legacy `codex-review-target` context is still emitted,
but only `codex-review-target / codex-review` is required. `iOS simulator` and `kimi-review`
run on every PR and are not required. Non-draft PRs use squash auto-merge; protected-path
Owner review still applies.
