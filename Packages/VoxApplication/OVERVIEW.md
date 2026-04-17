# VoxApplication overview

Purpose
- Use cases / application orchestration layer.

Public product
- `UseCases`

Depends on
- VoxDomain (`CoreModels`, `TextHistory`)
- VoxInfrastructure (`TranscriptionKit`, `LLMKit`, `Persistence`, `PlatformAdapters`, `Preferences`)
- LokiKit

Primary entry points
- `Packages/VoxApplication/Package.swift`
- `Packages/VoxApplication/Sources/UseCases/`

Recommended read order
1) `Packages/VoxApplication/Package.swift`
2) `Packages/VoxApplication/Sources/UseCases/`

Notes for LLM context
- Look for orchestrators and high-level workflows.
