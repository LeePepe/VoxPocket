# VoxInfrastructure overview

Purpose
- Platform services and adapters: LLM, transcription, persistence, observability.

Public products
- `TranscriptionKit`
- `LLMKit`
- `Persistence`
- `Observability`
- `PlatformAdapters`

Depends on
- VoxDomain (`CoreModels`, `TextHistory`)
- Swift Async Algorithms

Primary entry points
- `Packages/VoxInfrastructure/Package.swift`
- `Packages/VoxInfrastructure/Sources/LLMKit/`
- `Packages/VoxInfrastructure/Sources/TranscriptionKit/`
- `Packages/VoxInfrastructure/Sources/Persistence/`
- `Packages/VoxInfrastructure/Sources/Observability/`
- `Packages/VoxInfrastructure/Sources/PlatformAdapters/`

Recommended read order
1) `Packages/VoxInfrastructure/Package.swift`
2) `Packages/VoxInfrastructure/Sources/LLMKit/`
3) `Packages/VoxInfrastructure/Sources/TranscriptionKit/`
4) `Packages/VoxInfrastructure/Sources/Persistence/`
5) `Packages/VoxInfrastructure/Sources/Observability/`
6) `Packages/VoxInfrastructure/Sources/PlatformAdapters/`

Notes for LLM context
- Start with service boundaries and protocols, then implementations.
