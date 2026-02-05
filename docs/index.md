# VoxPocket - LLM Context Index

This index is the fastest entry point for loading repo context. Start here, then open only the referenced files.

## App entry points
- App root: `VoxPocket/VoxPocket/VoxPocketApp.swift`
- Xcode project: `VoxPocket/VoxPocket.xcodeproj`

## Package map (high level)
- VoxPresentation (UI layer)
  - Products: `UIShared`, `PlatformUI`
  - Depends on: VoxDomain, VoxInfrastructure, VoxApplication
- VoxApplication (use cases / app logic)
  - Product: `UseCases`
  - Depends on: VoxDomain, VoxInfrastructure
- VoxInfrastructure (platform + services)
  - Products: `TranscriptionKit`, `LLMKit`, `Persistence`, `Observability`, `PlatformAdapters`
  - Depends on: VoxDomain, Swift Async Algorithms
- VoxDomain (core models / pure domain)
  - Products: `CoreModels`, `TextHistory`

## Package entry files
Use these to anchor a quick scan of each package.

### VoxPresentation
- `Packages/VoxPresentation/Package.swift`
- UI shared entry areas:
  - `Packages/VoxPresentation/Sources/UIShared/Views/`
  - `Packages/VoxPresentation/Sources/UIShared/Models/`
  - `Packages/VoxPresentation/Sources/UIShared/Components/`
- Platform-specific UI:
  - `Packages/VoxPresentation/Sources/PlatformUI/`

### VoxApplication
- `Packages/VoxApplication/Package.swift`
- Use cases:
  - `Packages/VoxApplication/Sources/UseCases/`

### VoxInfrastructure
- `Packages/VoxInfrastructure/Package.swift`
- LLM + transcription:
  - `Packages/VoxInfrastructure/Sources/LLMKit/`
  - `Packages/VoxInfrastructure/Sources/TranscriptionKit/`
- Persistence + platform:
  - `Packages/VoxInfrastructure/Sources/Persistence/`
  - `Packages/VoxInfrastructure/Sources/PlatformAdapters/`
- Observability:
  - `Packages/VoxInfrastructure/Sources/Observability/`

### VoxDomain
- `Packages/VoxDomain/Package.swift`
- Core models:
  - `Packages/VoxDomain/Sources/CoreModels/`
- Text history:
  - `Packages/VoxDomain/Sources/TextHistory/`

## LLM quick path (recommended)
1) Read the package `Package.swift` file.
2) Jump to the top-level `Sources/<Target>/` directory.
3) Open the smallest set of files needed for the task.

## Open tabs snapshot (from IDE)
- `VoxPocket/VoxPocket/VoxPocketApp.swift`
- `Packages/VoxPresentation/Sources/UIShared/Models/SidebarDestination.swift`
- `Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift`
- `Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift`
