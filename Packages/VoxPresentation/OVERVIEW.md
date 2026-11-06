# VoxPresentation overview

Purpose
- UI layer. Shared UI lives in `UIShared`, platform-specific in `PlatformUI`.

Public products
- `UIShared`
- `PlatformUI`
- `WidgetUI`

Depends on
- VoxDomain (`CoreModels`, `TextHistory`)
- VoxInfrastructure (`VoxKitBridge`, `PlatformAdapters`)
- VoxKit (`VoxCore`, `VoxSpeech`, `VoxRefine`, `VoxLLM`)
- VoxApplication (`UseCases`)

Primary entry points
- `Packages/VoxPresentation/Package.swift`
- `Packages/VoxPresentation/Sources/UIShared/`
- `Packages/VoxPresentation/Sources/PlatformUI/`

Recommended read order
1) `Packages/VoxPresentation/Package.swift`
2) `Packages/VoxPresentation/Sources/UIShared/Views/`
3) `Packages/VoxPresentation/Sources/UIShared/Models/`
4) `Packages/VoxPresentation/Sources/PlatformUI/`

Notes for LLM context
- Start from top-level views and navigation models, then drill into components.
