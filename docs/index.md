# VoxPocket Context Index

Last-Reviewed: 2026-09-12

这是仓库的快速入口。先看这里，再按需下钻。

## Primary Entry Points

- Agent map: `AGENTS.md`
- Canonical records map: `docs/records/index.md`
- App root: `VoxPocket/VoxPocket/VoxPocketApp.swift`
- Xcode project source: `VoxPocket/project.yml` (XcodeGen)
- Build and delivery policy: `AGENTS.md` → TestFlight-only delivery
- Private runtime model configuration: `docs/architecture/private-model-config.md`

## Package Quick Map

- `VoxPresentation`: `UIShared`, `PlatformUI`
- `VoxApplication`: `UseCases`
- `VoxInfrastructure`: `TranscriptionKit`, `LLMKit`, `Persistence`, `PlatformAdapters`, `Preferences`
- `LokiKit`: 独立日志与遥测包
- `VoxDomain`: `CoreModels`, `TextHistory`

## Common Paths

- Architecture: `docs/architecture/`
- Plans: `docs/plans/`, `docs/superpowers/plans/`
- Current specs: `specs/`; historical specs: `docs/superpowers/specs/`
- Harness: `docs/harness/`
