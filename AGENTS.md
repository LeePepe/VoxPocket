# AGENTS.md — VoxPocket

Last-Reviewed: 2026-09-27

## Read first

- Before changes: [constitution](.specify/memory/constitution.md), then [architecture, owned paths and per-layer reading routes](docs/architecture/tech-context.md).
- Finding context: [documentation index](docs/index.md) and [records map](docs/records/index.md).

## Protocol

- Before implementation: [LeePepe/shared-ci@c389366a5c957c2442f5b7d5db40760acf3be43c/ai/agent-protocol.md](https://github.com/LeePepe/shared-ci/blob/c389366a5c957c2442f5b7d5db40760acf3be43c/ai/agent-protocol.md).
- Planning or changing specs: [Plan-Review Loop](docs/plans/README.md).
- Changing tests or preparing review: [repository review policy](docs/repository-policy.md).

## Verify

- Before local checks, commits or pushes: [verification and bootstrap](docs/local-gates.md).

## Required checks

- Before merging: [required checks and head-SHA evidence](docs/repository-policy.md#required-checks).

## Red lines

- Handling user content or credentials: [privacy and secrets principles](.specify/memory/constitution.md#core-principles) and [private configuration and repository hygiene](docs/architecture/private-model-config.md).

## Dependencies

- Changing dependencies: [external packages and authoritative pins](docs/architecture/tech-context.md#external-dependencies).

## Delivery

- Preparing a PR: [review boundaries](docs/repository-policy.md#review-and-execution-boundaries) and [PR template](.github/pull_request_template.md).
- Releasing an App build: [TestFlight delivery rules and release mechanics](docs/testflight-release.md).
