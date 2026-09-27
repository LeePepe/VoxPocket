# AGENTS.md — VoxPocket

Last-Reviewed: 2026-09-24

VoxPocket is a SwiftUI voice recording and transcription app for macOS and iOS
(default speech locale `zh-Hans`, text refinement with Apple Intelligence or a
configured provider). Every agent that edits it follows the protocol below.
Tool-specific files (CLAUDE.md etc.) only point here.

## Read first

1. `.specify/memory/constitution.md` — non-negotiable principles (immutability, layer
   direction, concurrency, privacy of voice/text, secrets hygiene, input validation)
2. `docs/architecture/tech-context.md` — layer table: layer → paths → depends_on
3. The leaf `tech-context.md` of every layer you touch
   (`python3 .shared-ci/scripts/context/_context.py contexts <path>` after one `scripts/verify`)
4. Index: `docs/index.md` · records map: `docs/records/index.md` · feature specs: `specs/`
   (Spec Kit, `.specify/`); historical plans: `docs/plans/`

Layer map (dependencies point down only; `LokiKit` and `AppleUITesting` are external):

```
VoxPocketApp (VoxPocket/**, VoxPocketWidget/**)   Xcode app shell, assembly, delivery
  → VoxPresentation   SwiftUI views and view models
  → VoxApplication    use cases
  → VoxInfrastructure transcription, LLM, persistence, platform adapters, preferences (+ LokiKit)
  → VoxDomain         pure domain models, no external dependencies
VoxUITesting          standalone test tooling (snapshot tests, Claude Vision UI eval)
```

A change that spans 2+ layers is too big: split it by layer. Fix a failure inside the
failing layer while honouring that layer's `red_lines`; a root cause elsewhere is a new task.

## Protocol

Follow `LeePepe/shared-ci@761fe6b0b3ca5e2c57d244182d495ab8041851fa/ai/agent-protocol.md`
(https://github.com/LeePepe/shared-ci/blob/761fe6b0b3ca5e2c57d244182d495ab8041851fa/ai/agent-protocol.md).
It must be the same SHA as the `uses:` pins in `.github/workflows/`.

Plan-Review Loop (mandatory for any implementation plan, spec or plan change; a test-only
change inside one layer with no production code change needs no plan, and its PR says so in
`Intent`):

1. Plan — a planner creates or updates the plan (`specs/` via Spec Kit, or `docs/plans/`).
2. Review — an independent reviewer reviews it immediately.
3. Revise — CRITICAL or MEDIUM findings are fixed in the plan.
4. Re-review — the reviewer reviews again without being asked.
5. Repeat until the reviewer outputs `APPROVED` with no CRITICAL finding.
6. Only then present the plan to the Owner for execution approval.

## Verify

```sh
git config core.hooksPath .githooks   # once per clone
scripts/verify            # changed layers vs origin/main + policy (what pre-push runs)
scripts/verify --all      # every layer gate + policy (what CI runs)
scripts/verify --policy   # policy only; scripts/verify --layer VoxDomain = one layer
```

- External packages live next to the repository: `../LokiKit` (LeePepe/shared-telemetry) and
  `../AppleUITesting`. `scripts/verify` runs `scripts/ci/fetch-external-deps.sh`, which checks
  out the pinned SHAs when missing. `scripts/verify` needs Python 3.11+ first on `PATH`.
- `pre-commit` keeps the fast staged-layer build/test plus docs map/freshness checks.
- Local verification is SPM build/test plus deterministic scripts. The app-target
  `xcodebuild` runs in CI only (`RUN_HEAVY=1 scripts/verify` opts in locally).
- Never `--no-verify`, never weaken or skip tests, never edit policy/gates to pass.

## Required checks

Merging to `main` requires (must match the live ruleset `main protection`, mirrored in
`scripts/rulesets/main-protection.json`):

- `quality / aggregate`
- `codex-review-target / codex-review`
- `SPM VoxDomain`
- `SPM VoxInfrastructure`
- `SPM VoxApplication`
- `SPM VoxPresentation`
- `SPM VoxUITesting`
- `App target`
- `Lint & policy`

The ruleset also requires CODEOWNERS review (0 extra approvals) and dismisses stale reviews on
push. It does not require the branch to be up to date (`strict` off). Owner-approved R3
(2026-09-24) made that trade: `quality / aggregate` fails unless every lane passed on the PR
head SHA (and the PR body is complete), and stale reviews are dismissed on push, so evidence
is always for the head being merged.
`codex-review-target / codex-review` replaced the legacy `codex-review-target` context,
which the workflow still emits but is not required. `iOS simulator` and `kimi-review` run on
every PR and are never required.

## Red lines

- Privacy (constitution IV): recorded audio, transcripts and refined text never go into
  logs or telemetry payloads (metrics only: durations, counts, source labels, session IDs),
  and never leave the app sandbox (`~/Library/Application Support/VoxPocket/`).
- Secrets (constitution V): no keys or tokens in source. Keys come from environment
  variables. Azure model credentials may come from the runtime-only sandbox file
  `config.private.json` (owner-only 0600, excluded from backups, Git and app bundles,
  contents and decoder errors never logged); only the empty `config.example.json` template
  is committed. Read `docs/architecture/private-model-config.md` before touching it.
- No Microsoft/Azure resource identifiers, real endpoints, tenant IDs or other
  project-specific non-public values in Git (code, tests, fixtures, docs). Use synthetic
  `example-*` values; real values stay in gitignored local files with a committed template.
- Delivery is TestFlight only: every user-facing macOS/iOS App build goes through
  `.github/workflows/testflight.yml` (manual `workflow_dispatch` after an explicit Owner
  request). Agents do not create local archives, install, replace or launch delivery builds,
  or sign in to App Store Connect. Upload success is not "testable"; the Owner verifies.
- Platforms: macOS is released via TestFlight. iOS is enabled for development with CI
  build/test; iOS TestFlight releases need separate Owner authorization.
- `VoxPocket/project.yml` (XcodeGen) is the source of truth for the Xcode project.
- Changes to `.github/**`, hooks, `scripts/verify`, rulesets, tech-context or AGENTS/
  constitution are important PRs.
- No personal account names, credential-profile paths or local home paths in the repo.

Approved exceptions: none.

## Dependencies

- `shared-ci` `761fe6b0b3ca5e2c57d244182d495ab8041851fa` — https://github.com/LeePepe/shared-ci/blob/761fe6b0b3ca5e2c57d244182d495ab8041851fa/ai/
- LokiKit from LeePepe/shared-telemetry at `eff9c1712cd648ed0717e41183ad8bd7bf39cbea` (no tag
  or `ai/` bundle yet; pinned in `scripts/ci/fetch-external-deps.sh`).
- AppleUITesting at `e6be2fcdf83341a9f3000a4cc489237655461a07` (same script).

## Delivery

- One task → one branch + worktree → one PR using `.github/pull_request_template.md`.
- Done = required checks green on the PR head SHA; a new push invalidates old evidence.
- Non-draft PRs get squash auto-merge (`auto-merge.yml`). CODEOWNERS paths (`.github/**`,
  policy/schemas/gates, AGENTS.md, constitution, dependency pins) need Owner approval, which
  the ruleset enforces (code-owner review required); add the `owner-review` label to them.
- Code tasks report the commit, verification and PR. For an authorized TestFlight run,
  report version/build number, run link and distribution warnings. Keep existing local
  artifacts; do not clean them up automatically.
