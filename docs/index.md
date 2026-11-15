# VoxPocket Context Index

Last-Reviewed: 2026-11-15

这是仓库的快速入口。先看这里，再按需下钻。

## Primary Entry Points

- Agent map: `AGENTS.md`
- Canonical records map: `docs/records/index.md`
- App root: `VoxPocket/VoxPocket/VoxPocketApp.swift`
- Xcode project source: `VoxPocket/project.yml` (XcodeGen)
- Build and delivery policy: `AGENTS.md` → Red lines (TestFlight-only delivery); release mechanics: `docs/testflight-release.md`
- Runtime architecture notes (flows, providers, env vars, telemetry): `docs/architecture/runtime-notes.md`
- Verification entry: `scripts/verify` (see `docs/local-gates.md`)
- Private runtime model configuration: `docs/architecture/private-model-config.md`

## Package Quick Map

- `VoxPresentation`: `UIShared`, `PlatformUI`
- `VoxApplication`: `UseCases`
- `VoxInfrastructure`: `VoxKitBridge`, `Persistence`, `PlatformAdapters`, `Preferences`
- `LokiKit`: 独立日志与遥测包
- `VoxDomain`: `CoreModels`, `TextHistory`
- `VoxPocketKit`: Watch capture, transport, receipt and iPhone ingest seams
- `VoxKit`: remote standalone SDK (`LeePepe/VoxKit`, exact `0.1.0`; `VoxCore`, `VoxSpeech`, `VoxSpeechWhisperKit`, `VoxRefine`, `VoxLLM`, `VoxWorkflow`)

## Common Paths

- Architecture: `docs/architecture/`
- Plans: `docs/plans/`, `docs/superpowers/plans/`
- Watch Kit approved implementation record: `docs/plans/voxpocket-watch-kit.md`
- Current specs: `specs/`; historical specs: `docs/superpowers/specs/`
- Harness: `docs/harness/`

- Design contract: `docs/design-contract.md`
